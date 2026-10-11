"""
Synced game nights: the schema, the validation and the merge rules.

Nothing in here touches Firebase, so the rules that decide whose edit wins —
and what a deleted night leaves behind — can be tested exhaustively. Storage
lives in firebase.py and the HTTP layer in main.py.

Wire format
-----------
The JSON is the one the iOS app writes to its own files (NightCoding.swift):
camelCase keys, money in whole minor units (cents), instants as ISO-8601 UTC
with milliseconds ("2026-08-06T19:00:00.123Z"). The server stores exactly that,
plus `serverUpdatedAt` — a server-assigned, fixed-width UTC timestamp that the
incremental pull (`since`) is ordered by.

Conflict rule
-------------
Last writer wins, judged by the client's `updatedAt`. A night is replaced only
by a strictly later edit. Re-sending the version the server already holds
changes nothing, so a retry after a dropped connection is harmless; a tie with
different content keeps what the server has, and the loser is handed that
version, so every device converges on one answer.

Deleting
--------
A deleted night is kept as a tombstone: its id, start time, zone, currency and
the two timestamps — nothing about who played, where or for how much. Other
devices need the marker to stop showing the night, and a later "undo" (a newer,
un-deleted version) can still win over it.
"""

from __future__ import annotations

import re
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Annotated, Any, Dict, List, Literal, Optional

from pydantic import (
    AfterValidator,
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    ValidationError,
    field_validator,
    model_validator,
)

SCHEMA_VERSION = 1

MAX_MINOR = 100_000_000  # $1,000,000.00 in one buy-in
MAX_CASH_OUT_MINOR = 1_000_000_000
MAX_PLAYERS = 30
MAX_BUY_INS = 200
MAX_PAUSES = 500
MAX_COLORS = 12
MAX_BODY_BYTES = 128 * 1024

_EARLIEST = datetime(2000, 1, 1, tzinfo=timezone.utc)
_LATEST = datetime(2100, 1, 1, tzinfo=timezone.utc)

# Firestore rejects map keys that look like __reserved__, so chip colours are
# kept to plain words.
_COLOR_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _-]{0,31}$")


def _canonical_uuid(value: str) -> str:
    try:
        return str(uuid.UUID(value)).upper()
    except (ValueError, AttributeError, TypeError):
        raise ValueError("must be a UUID")


def _color_name(value: str) -> str:
    if not _COLOR_PATTERN.match(value):
        raise ValueError("must be a short plain name")
    return value


UUIDString = Annotated[str, AfterValidator(_canonical_uuid)]
ColorName = Annotated[str, AfterValidator(_color_name)]
Instant = Annotated[AwareDatetime, Field(ge=_EARLIEST, le=_LATEST)]


class _Strict(BaseModel):
    # Unknown fields are refused rather than silently dropped: a newer app
    # talking to an older server fails loudly, and the night stays safe on the
    # phone, instead of losing the new field on the way through.
    model_config = ConfigDict(extra="forbid")


class BuyInModel(_Strict):
    id: UUIDString
    amountMinor: int = Field(gt=0, le=MAX_MINOR)
    at: Instant


class PlayerModel(_Strict):
    id: UUIDString
    name: str = Field(min_length=1, max_length=40)
    buyIns: List[BuyInModel] = Field(min_length=1, max_length=MAX_BUY_INS)
    cashOutMinor: Optional[int] = Field(default=None, ge=0, le=MAX_CASH_OUT_MINOR)
    cashedOutAt: Optional[Instant] = None

    @field_validator("name")
    @classmethod
    def _name_not_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("must not be blank")
        return value


class BlindsModel(_Strict):
    smallMinor: int = Field(ge=0, le=MAX_MINOR)
    bigMinor: int = Field(ge=0, le=MAX_MINOR)


class PauseModel(_Strict):
    start: Instant
    end: Optional[Instant] = None


class ResolutionModel(_Strict):
    kind: Literal["tip", "assign", "split"]
    playerID: Optional[UUIDString] = None
    deltaMinor: int = Field(ge=-MAX_CASH_OUT_MINOR, le=MAX_CASH_OUT_MINOR)


class NightModel(_Strict):
    schemaVersion: int = Field(default=SCHEMA_VERSION, ge=1, le=SCHEMA_VERSION)
    id: UUIDString
    startedAt: Instant
    endedAt: Optional[Instant] = None
    settledAt: Optional[Instant] = None
    tzIdentifier: str = Field(default="UTC", min_length=1, max_length=64)
    currency: str = Field(default="USD", pattern=r"^[A-Z]{3}$")
    defaultBuyInMinor: int = Field(ge=0, le=MAX_MINOR)
    blinds: Optional[BlindsModel] = None
    location: Optional[str] = Field(default=None, max_length=80)
    notes: Optional[str] = Field(default=None, max_length=2000)
    colors: List[ColorName] = Field(default_factory=list, max_length=MAX_COLORS)
    denominationsMinor: Dict[ColorName, int] = Field(default_factory=dict, max_length=MAX_COLORS)
    startingCounts: Optional[Dict[ColorName, int]] = Field(default=None, max_length=MAX_COLORS)
    players: List[PlayerModel] = Field(max_length=MAX_PLAYERS)
    myPlayerID: Optional[UUIDString] = None
    pauses: List[PauseModel] = Field(default_factory=list, max_length=MAX_PAUSES)
    resolution: Optional[ResolutionModel] = None
    updatedAt: Instant
    deletedAt: Optional[Instant] = None
    source: Optional[str] = Field(default=None, max_length=32)

    @field_validator("denominationsMinor")
    @classmethod
    def _values_positive(cls, value: Dict[str, int]) -> Dict[str, int]:
        if any(not 0 < v <= MAX_MINOR for v in value.values()):
            raise ValueError("chip values must be between 1 and the maximum")
        return value

    @field_validator("startingCounts")
    @classmethod
    def _counts_sane(cls, value: Optional[Dict[str, int]]) -> Optional[Dict[str, int]]:
        if value is not None and any(not 0 <= v <= 10_000 for v in value.values()):
            raise ValueError("chip counts must be between 0 and 10,000")
        return value

    @model_validator(mode="after")
    def _players_are_distinct(self) -> "NightModel":
        ids = [player.id for player in self.players]
        if len(set(ids)) != len(ids):
            raise ValueError("players must have distinct ids")
        return self


# ---------------------------------------------------------------- canonical form

def format_instant(moment: datetime) -> str:
    """"2026-08-06T19:00:00.123Z": UTC, whole milliseconds, always the same width,
    so these strings sort chronologically and match what the iOS encoder writes."""
    moment = moment.astimezone(timezone.utc)
    return f"{moment:%Y-%m-%dT%H:%M:%S}.{moment.microsecond // 1000:03d}Z"


def parse_instant(value: str) -> datetime:
    """The inverse of `format_instant` (and tolerant of any ISO-8601 UTC offset)."""
    return datetime.fromisoformat(value).astimezone(timezone.utc)


def _canonical(value: Any) -> Any:
    if isinstance(value, datetime):
        return format_instant(value)
    if isinstance(value, dict):
        return {key: _canonical(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_canonical(item) for item in value]
    return value


def to_document(night: NightModel) -> Dict[str, Any]:
    """The night as JSON-ready data in its canonical form (absent optionals left out)."""
    return _canonical(night.model_dump(mode="python", exclude_none=True))


def tombstone_of(document: Dict[str, Any]) -> Dict[str, Any]:
    """What survives deletion. Keep this in step with `GameNight.tombstone` in the app."""
    return {
        "schemaVersion": document["schemaVersion"],
        "id": document["id"],
        "startedAt": document["startedAt"],
        "tzIdentifier": document["tzIdentifier"],
        "currency": document["currency"],
        "defaultBuyInMinor": 0,
        "colors": [],
        "denominationsMinor": {},
        "players": [],
        "pauses": [],
        "updatedAt": document["updatedAt"],
        "deletedAt": document["deletedAt"],
    }


def stored_form(night: NightModel) -> Dict[str, Any]:
    """What the server keeps: the night, or just its tombstone if it was deleted."""
    document = to_document(night)
    return tombstone_of(document) if document.get("deletedAt") else document


def public_form(stored: Dict[str, Any]) -> Dict[str, Any]:
    """A stored night as sent to clients: without the server's bookkeeping."""
    return {key: value for key, value in stored.items() if key != "serverUpdatedAt"}


def describe(error: ValidationError) -> str:
    """A short, safe description of what was wrong. Never repeats the input, which
    holds players' names."""
    problems = []
    for item in error.errors(include_input=False, include_url=False)[:3]:
        where = ".".join(str(part) for part in item["loc"]) or "night"
        problems.append(f"{where}: {item['msg']}")
    return "That night couldn't be saved — " + "; ".join(problems)


# ----------------------------------------------------------------- merge rule

@dataclass(frozen=True)
class PutDecision:
    write: bool    # store the offered version
    applied: bool  # the server now holds the offered version


def decide_put(existing: Optional[Dict[str, Any]], offered: Dict[str, Any]) -> PutDecision:
    """Whose version is kept. Both arguments are in stored form."""
    if existing is None:
        return PutDecision(write=True, applied=True)
    held_at, offered_at = existing["updatedAt"], offered["updatedAt"]  # fixed-width UTC: string order is time order
    if offered_at > held_at:
        return PutDecision(write=True, applied=True)
    if offered_at == held_at and public_form(existing) == public_form(offered):
        return PutDecision(write=False, applied=True)
    return PutDecision(write=False, applied=False)


def normalize_cursor(raw: str) -> str:
    """A `since` value in the exact form `serverUpdatedAt` is stored in."""
    try:
        moment = datetime.fromisoformat(raw)
    except ValueError:
        raise ValueError("since must be an ISO-8601 timestamp")
    if moment.tzinfo is None:
        raise ValueError("since must include a time zone")
    return moment.astimezone(timezone.utc).isoformat(timespec="microseconds")


# -------------------------------------------------------------- legacy import

# Fixed forever: the ids of imported nights are derived from it, which is what
# makes importing the same old session twice a no-op.
_LEGACY_NAMESPACE = uuid.UUID("5b0b7a0e-6d0c-4c42-9a55-1f2f2f6f9a10")


def _parse_stored_instant(value: Any) -> datetime:
    moment = datetime.fromisoformat(str(value))
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


def legacy_night(uid: str, session_id: str, record: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """A one-player night for a session saved by the single-player app, in stored
    form, or None if the record is incomplete or unusable. Rebuy segments of one
    old night stay separate nights."""
    if record.get("status") != "complete":
        return None
    try:
        buy_in = record["buyInCents"] if record.get("buyInCents") is not None else round(float(record["buyIn"]) * 100)
        cash_out = (
            record["endingValueCents"]
            if record.get("endingValueCents") is not None
            else round(float(record["endingValue"]) * 100)
        )
        elapsed = max(0, int(record.get("elapsedSeconds") or 0))
        created = _parse_stored_instant(record["createdAt"])
        started = _parse_stored_instant(record["startedAt"]) if record.get("startedAt") else created - timedelta(seconds=elapsed)
        ended = started + timedelta(seconds=elapsed)
        updated = _parse_stored_instant(record["updatedAt"]) if record.get("updatedAt") else created
        denominations = {
            color: round(float(value) * 100)
            for color, value in (record.get("denominations") or {}).items()
            if float(value) > 0
        }
        colors = sorted(denominations, key=lambda color: (denominations[color], color))
        base = f"{uid}:{session_id}"
        candidate = {
            "schemaVersion": SCHEMA_VERSION,
            "id": str(uuid.uuid5(_LEGACY_NAMESPACE, base)),
            "startedAt": started,
            "endedAt": ended,
            "settledAt": max(ended, created),
            "tzIdentifier": record.get("tzIdentifier") or "UTC",
            "currency": "USD",
            "defaultBuyInMinor": int(buy_in),
            "colors": colors,
            "denominationsMinor": denominations,
            "myPlayerID": str(uuid.uuid5(_LEGACY_NAMESPACE, base + ":player")),
            "players": [{
                "id": str(uuid.uuid5(_LEGACY_NAMESPACE, base + ":player")),
                "name": "Me",
                "buyIns": [{
                    "id": str(uuid.uuid5(_LEGACY_NAMESPACE, base + ":buy-in")),
                    "amountMinor": int(buy_in),
                    "at": started,
                }],
                "cashOutMinor": int(cash_out),
                "cashedOutAt": max(ended, created),
            }],
            "updatedAt": updated,
            "source": "legacy-session",
        }
        return to_document(NightModel.model_validate(candidate))
    except (KeyError, TypeError, ValueError, ValidationError, AttributeError):
        return None
