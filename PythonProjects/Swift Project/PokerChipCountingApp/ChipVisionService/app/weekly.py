"""
The "Poker Health" weekly aggregation, kept free of Firestore so it can be
tested against fixed clocks and time zones.

Two rules the earlier version got wrong:
  * Days are the *player's* local calendar days, not UTC ones — an 8 pm Pacific
    session is still "today", even though it is already tomorrow in UTC.
  * The total is the sum of the bars, never counted separately, so the two can
    never disagree at the edge of the 7-day window.

A session is attributed to the local day it *started* on. One that runs past
midnight is not split across two bars.
"""

from datetime import date, datetime, timedelta, timezone
from typing import Dict, Iterable, List, Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

WINDOW_DAYS = 7


def resolve_timezone(name: Optional[str]) -> ZoneInfo:
    """The caller's IANA zone, or UTC if it's missing or unknown — a bad
    client string should degrade the bucketing, not fail the request."""
    if not name:
        return ZoneInfo("UTC")
    try:
        return ZoneInfo(name)
    except (ZoneInfoNotFoundError, ValueError):
        return ZoneInfo("UTC")


def _parse_utc(value) -> Optional[datetime]:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str) and value:
        try:
            parsed = datetime.fromisoformat(value)
        except ValueError:
            return None
    else:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def session_start(data: Dict) -> Optional[datetime]:
    """When the session began, in UTC. Sessions saved before `startedAt`
    existed fall back to completion time minus the time played."""
    started = _parse_utc(data.get("startedAt"))
    if started is not None:
        return started
    completed = _parse_utc(data.get("createdAt"))
    if completed is None:
        return None
    seconds = max(0, int(data.get("elapsedSeconds", 0) or 0))
    return completed - timedelta(seconds=seconds)


def window_dates(now_utc: datetime, tz: ZoneInfo) -> List[date]:
    """The last 7 local days, oldest first, ending with today."""
    today = now_utc.astimezone(tz).date()
    return [today - timedelta(days=offset) for offset in range(WINDOW_DAYS - 1, -1, -1)]


def window_start_utc(now_utc: datetime, tz: ZoneInfo) -> datetime:
    """Local midnight at the start of the window, as a UTC instant — a safe
    lower bound for a `createdAt >=` query, since a session can't complete
    before it started."""
    oldest = window_dates(now_utc, tz)[0]
    return datetime(oldest.year, oldest.month, oldest.day, tzinfo=tz).astimezone(timezone.utc)


def summarize_week(sessions: Iterable[Dict], tz: ZoneInfo, now_utc: datetime) -> Dict:
    totals: Dict[date, int] = {day: 0 for day in window_dates(now_utc, tz)}
    for data in sessions:
        start = session_start(data)
        if start is None:
            continue
        local_day = start.astimezone(tz).date()
        if local_day in totals:
            totals[local_day] += max(0, int(data.get("elapsedSeconds", 0) or 0))

    return {
        "totalSeconds": sum(totals.values()),
        "days": [{"date": day.isoformat(), "seconds": seconds} for day, seconds in totals.items()],
    }
