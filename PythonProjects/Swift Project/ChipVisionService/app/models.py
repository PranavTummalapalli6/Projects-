from typing import Dict

from pydantic import BaseModel


class ChipDetectionResponse(BaseModel):
    counts: Dict[str, int]
    confidence: str
    photoUrl: str


class CompleteSessionRequest(BaseModel):
    buyIn: float
    denominations: Dict[str, float]
    finalCounts: Dict[str, int]
    elapsedSeconds: int


class CompleteSessionResponse(BaseModel):
    profitLoss: float
    photoUrl: str
