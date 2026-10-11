from app.logging_config import JsonFormatter, uid_tag
from app.ratelimit import SlidingWindowLimiter

import json
import logging


class Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


def test_limiter_allows_up_to_the_limit_then_blocks_until_the_window_passes():
    clock = Clock()
    limiter = SlidingWindowLimiter(limit=3, window_seconds=60, clock=clock)

    assert [limiter.allow("u1") for _ in range(4)] == [True, True, True, False]
    clock.now += 59
    assert limiter.allow("u1") is False
    clock.now += 2
    assert limiter.allow("u1") is True


def test_limits_are_tracked_per_user():
    limiter = SlidingWindowLimiter(limit=1, window_seconds=60, clock=Clock())
    assert limiter.allow("u1") is True
    assert limiter.allow("u1") is False
    assert limiter.allow("u2") is True


def test_uid_tag_is_stable_short_and_not_the_uid():
    assert uid_tag("abc123") == uid_tag("abc123")
    assert uid_tag("abc123") != uid_tag("abc124")
    assert "abc123" not in uid_tag("abc123") and len(uid_tag("abc123")) == 10


def test_json_logs_carry_severity_message_and_fields():
    record = logging.LogRecord("svc", logging.WARNING, __file__, 1, "photo_analyzed", None, None)
    record.fields = {"uid": "deadbeef", "chips": 27}
    payload = json.loads(JsonFormatter().format(record))

    assert payload["severity"] == "WARNING"
    assert payload["message"] == "photo_analyzed"
    assert payload["uid"] == "deadbeef" and payload["chips"] == 27
