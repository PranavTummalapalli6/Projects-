"""
Structured (JSON) logging. Cloud Run's log viewer reads `severity` and
`message` from JSON lines, so a request's fields stay filterable instead of
being buried in a formatted string.

Never log emails, photos or raw Firebase uids: use `uid_tag()` — a short
one-way hash that still lets one user's requests be followed in the logs.
"""

import hashlib
import json
import logging
import sys


def uid_tag(uid: str) -> str:
    return hashlib.sha256(uid.encode("utf-8")).hexdigest()[:10]


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "severity": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
            "time": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
        }
        fields = getattr(record, "fields", None)
        if isinstance(fields, dict):
            payload.update(fields)
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def configure_logging(level: int = logging.INFO) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level)
