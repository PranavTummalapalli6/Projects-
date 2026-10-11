from datetime import datetime
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field, field_validator


class DetectionModel(BaseModel):
    # Centre and radius as fractions of the photo's width (see chip_detection.Detection).
    x: float
    y: float
    r: float
    color: str


class StackModel(BaseModel):
    # One pile of chips seen from the side. Centre and size are fractions of the
    # photo's width; `angle` is how far to turn a box drawn there (the camera's roll).
    x: float
    y: float
    w: float
    h: float
    angle: float = 0
    color: str
    count: int
    confidence: str


class ChipDetectionResponse(BaseModel):
    counts: Dict[str, int]
    confidence: str
    # Where each counted chip is, for the annotated-photo review. Added after the
    # first release of the endpoint: an older app ignores it, and an app talking
    # to an older server treats its absence as "no overlay".
    detections: List[DetectionModel] = []
    # For a photo taken from the side: each pile and how many chips it holds. Empty
    # for a top-down photo, and from a server that predates it.
    stacks: List[StackModel] = []
    # Which counter read the photo: "top" (circles) or "side" (piles).
    view: str = "top"
    # Short-lived signed URL for the stored (private) photo; "" if storage was
    # unavailable and only the detection result could be returned.
    photoUrl: str


class CompleteSessionRequest(BaseModel):
    buyIn: float = Field(gt=0, le=1_000_000)
    denominations: Dict[str, float]
    finalCounts: Dict[str, int]
    # Seconds played in *this* segment only. A rebuy continues the on-screen
    # clock, but each stored session must count only its own playtime — the
    # weekly summary sums this field, so a cumulative value would double-count
    # every earlier segment of the same night.
    elapsedSeconds: int = Field(ge=0, le=7 * 24 * 3600)
    # All optional so older app builds that don't send them keep working.
    startedAt: Optional[datetime] = None
    tzIdentifier: Optional[str] = Field(default=None, max_length=64)
    sessionGroupId: Optional[str] = Field(default=None, max_length=64)

    @field_validator("denominations")
    @classmethod
    def _denominations_positive(cls, value: Dict[str, float]) -> Dict[str, float]:
        if any(v <= 0 for v in value.values()):
            raise ValueError("chip values must be greater than zero")
        return value

    @field_validator("finalCounts")
    @classmethod
    def _counts_non_negative(cls, value: Dict[str, int]) -> Dict[str, int]:
        if any(v < 0 for v in value.values()):
            raise ValueError("chip counts cannot be negative")
        return value


class CompleteSessionResponse(BaseModel):
    profitLoss: float
    profitLossCents: int
    photoUrl: str


class PhotoUrlResponse(BaseModel):
    photoUrl: str
    expiresInSeconds: int


class DaySummary(BaseModel):
    date: str
    seconds: int


class WeeklySummaryResponse(BaseModel):
    totalSeconds: int
    days: List[DaySummary]


class PutNightResponse(BaseModel):
    # The version the server now holds. When `applied` is false that is the
    # server's own (later) version, which the app adopts.
    night: Dict[str, Any]
    applied: bool
    serverUpdatedAt: str


class NightPage(BaseModel):
    nights: List[Dict[str, Any]]
    # Pass back as `since` to continue; null only if nothing has ever been stored.
    cursor: Optional[str] = None
    hasMore: bool


class ImportLegacyResponse(BaseModel):
    imported: int
