"""
A small per-user sliding-window limiter for the one expensive endpoint (photo
analysis runs OpenCV on every call).

It lives in process memory, so each instance enforces its own limit: that is
enough to blunt a runaway client or casual abuse, but it is not a global quota.
If the service ever runs many instances and a hard cap matters, move the
counters to a shared store.
"""

import time
from collections import defaultdict, deque
from typing import Callable, Deque, Dict


class SlidingWindowLimiter:
    def __init__(self, limit: int, window_seconds: float, clock: Callable[[], float] = time.monotonic):
        self.limit = limit
        self.window_seconds = window_seconds
        self._clock = clock
        self._hits: Dict[str, Deque[float]] = defaultdict(deque)

    def allow(self, key: str) -> bool:
        now = self._clock()
        hits = self._hits[key]
        while hits and now - hits[0] >= self.window_seconds:
            hits.popleft()
        if len(hits) >= self.limit:
            return False
        hits.append(now)
        return True
