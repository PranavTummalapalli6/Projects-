from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from app.weekly import (
    resolve_timezone,
    session_start,
    summarize_week,
    window_dates,
    window_start_utc,
)

LA = ZoneInfo("America/Los_Angeles")
KOLKATA = ZoneInfo("Asia/Kolkata")


def _session(start_local: datetime, minutes: int) -> dict:
    """A stored session record as the backend writes it."""
    start_utc = start_local.astimezone(timezone.utc)
    end_utc = start_utc + timedelta(minutes=minutes)
    return {
        "startedAt": start_utc.isoformat(),
        "createdAt": end_utc.isoformat(),
        "elapsedSeconds": minutes * 60,
    }


def _bars(summary: dict) -> dict:
    return {day["date"]: day["seconds"] for day in summary["days"]}


def test_rebuy_night_counts_each_segment_once_in_los_angeles():
    # One night, three rebuy segments (60 + 30 + 45 min); the last starts at
    # 23:30 and runs past midnight. The player's calendar day is Aug 5 for
    # all of it, even though every one of these instants is already Aug 6 in UTC.
    night = [
        _session(datetime(2026, 8, 5, 19, 0, tzinfo=LA), 60),
        _session(datetime(2026, 8, 5, 20, 0, tzinfo=LA), 30),
        _session(datetime(2026, 8, 5, 23, 30, tzinfo=LA), 45),
    ]
    now = datetime(2026, 8, 6, 12, 0, tzinfo=timezone.utc)  # 05:00 PDT, Aug 6

    summary = summarize_week(night, LA, now)

    assert summary["totalSeconds"] == 135 * 60
    bars = _bars(summary)
    assert bars["2026-08-05"] == 135 * 60
    assert bars["2026-08-06"] == 0
    assert sum(bars.values()) == summary["totalSeconds"]


def test_rebuy_night_counts_each_segment_once_in_kolkata():
    # Kolkata is ahead of UTC, so the failure runs the other way: a session
    # starting at 00:15 on Aug 6 local is still Aug 5 in UTC.
    night = [
        _session(datetime(2026, 8, 5, 20, 0, tzinfo=KOLKATA), 60),
        _session(datetime(2026, 8, 5, 21, 0, tzinfo=KOLKATA), 30),
        _session(datetime(2026, 8, 5, 23, 30, tzinfo=KOLKATA), 45),
        _session(datetime(2026, 8, 6, 0, 15, tzinfo=KOLKATA), 20),
    ]
    now = datetime(2026, 8, 6, 12, 0, tzinfo=timezone.utc)  # 17:30 IST, Aug 6

    summary = summarize_week(night, KOLKATA, now)

    bars = _bars(summary)
    assert bars["2026-08-05"] == 135 * 60
    assert bars["2026-08-06"] == 20 * 60
    assert summary["totalSeconds"] == 155 * 60


def test_total_is_always_the_sum_of_the_bars_at_the_window_edge():
    now = datetime(2026, 8, 6, 12, 0, tzinfo=timezone.utc)
    days = window_dates(now, LA)
    assert len(days) == 7
    oldest = days[0]

    inside_edge = _session(datetime(oldest.year, oldest.month, oldest.day, 0, 1, tzinfo=LA), 40)
    just_outside = _session(
        datetime(oldest.year, oldest.month, oldest.day, 23, 50, tzinfo=LA) - timedelta(days=1), 90
    )

    summary = summarize_week([inside_edge, just_outside], LA, now)

    assert summary["totalSeconds"] == 40 * 60
    assert sum(day["seconds"] for day in summary["days"]) == summary["totalSeconds"]


def test_window_is_seven_local_days_oldest_first_ending_today():
    now = datetime(2026, 8, 6, 3, 0, tzinfo=timezone.utc)  # 20:00 PDT on Aug 5
    days = window_dates(now, LA)
    assert [d.isoformat() for d in days] == [
        "2026-07-30", "2026-07-31", "2026-08-01", "2026-08-02",
        "2026-08-03", "2026-08-04", "2026-08-05",
    ]


def test_window_start_is_local_midnight_of_the_oldest_day_in_utc():
    now = datetime(2026, 8, 5, 10, 0, tzinfo=timezone.utc)  # 03:00 PDT, Aug 5
    # Oldest day is Jul 30; local midnight PDT (UTC-7) is 07:00 UTC.
    assert window_start_utc(now, LA) == datetime(2026, 7, 30, 7, 0, tzinfo=timezone.utc)


def test_window_start_handles_a_daylight_saving_change_inside_the_window():
    new_york = ZoneInfo("America/New_York")
    now = datetime(2026, 11, 2, 12, 0, tzinfo=timezone.utc)  # 07:00 EST, Nov 2
    # Oldest day is Oct 27, still EDT (UTC-4): local midnight is 04:00 UTC.
    assert window_start_utc(now, new_york) == datetime(2026, 10, 27, 4, 0, tzinfo=timezone.utc)
    # The clocks went back on Nov 1, so the bar for that 25-hour day still counts once.
    sessions = [_session(datetime(2026, 11, 1, 1, 30, tzinfo=new_york), 50)]
    assert _bars(summarize_week(sessions, new_york, now))["2026-11-01"] == 50 * 60


def test_sessions_saved_before_started_at_existed_fall_back_to_completion_minus_elapsed():
    completed = datetime(2026, 8, 5, 23, 40, tzinfo=LA).astimezone(timezone.utc)
    legacy = {"createdAt": completed.isoformat(), "elapsedSeconds": 3 * 3600}
    # Started 20:40 PDT Aug 5 — same local day as it finished.
    assert session_start(legacy) == completed - timedelta(hours=3)

    now = datetime(2026, 8, 6, 12, 0, tzinfo=timezone.utc)
    assert _bars(summarize_week([legacy], LA, now))["2026-08-05"] == 3 * 3600


def test_records_without_any_usable_timestamp_are_skipped_not_fatal():
    now = datetime(2026, 8, 6, 12, 0, tzinfo=timezone.utc)
    junk = [{"elapsedSeconds": 600}, {"createdAt": "not a date", "elapsedSeconds": 600}]
    assert summarize_week(junk, LA, now)["totalSeconds"] == 0


def test_unknown_or_missing_timezone_degrades_to_utc():
    assert resolve_timezone(None).key == "UTC"
    assert resolve_timezone("Mars/Olympus_Mons").key == "UTC"
    assert resolve_timezone("America/Los_Angeles").key == "America/Los_Angeles"
