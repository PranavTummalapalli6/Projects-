import json
import logging
from contextlib import asynccontextmanager
from typing import Optional

import cv2
import numpy as np
from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile, status

from app.chip_detection import detect_chips
from app.firebase import init_firebase, save_session, upload_photo, verify_token
from app.models import (
    ChipDetectionResponse,
    CompleteSessionRequest,
    CompleteSessionResponse,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("chip-vision-service")

# Maps "{uid}:{sessionId}" -> photoUrl so /complete can attach the photo saved by
# /photo without the client needing to pass it back. Fine for a single-instance
# demo; a multi-instance deployment should look this up from Firestore instead.
_session_photo_urls: dict[str, str] = {}


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_firebase()
    yield


app = FastAPI(title="ChipVisionService", lifespan=lifespan)


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


def _bearer_uid(authorization: Optional[str]) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing 'Authorization: Bearer <token>' header",
        )
    token = authorization.removeprefix("Bearer ").strip()
    return verify_token(token)


@app.post("/v1/sessions/{session_id}/photo", response_model=ChipDetectionResponse)
async def analyze_photo(
    session_id: str,
    image: UploadFile = File(...),
    denominations: str = Form(...),
    authorization: Optional[str] = Header(None),
):
    uid = _bearer_uid(authorization)

    try:
        json.loads(denominations)
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="denominations must be valid JSON")

    raw_bytes = await image.read()
    np_array = np.frombuffer(raw_bytes, dtype=np.uint8)
    image_bgr = cv2.imdecode(np_array, cv2.IMREAD_COLOR)
    if image_bgr is None:
        raise HTTPException(status_code=400, detail="Could not decode image")

    counts, confidence = detect_chips(image_bgr)
    photo_url = upload_photo(uid, session_id, raw_bytes)
    _session_photo_urls[f"{uid}:{session_id}"] = photo_url

    logger.info(
        "session=%s uid=%s detected=%s confidence=%s",
        session_id, uid, counts, confidence,
    )
    return ChipDetectionResponse(counts=counts, confidence=confidence, photoUrl=photo_url)


@app.post("/v1/sessions/{session_id}/complete", response_model=CompleteSessionResponse)
async def complete_session(
    session_id: str,
    body: CompleteSessionRequest,
    authorization: Optional[str] = Header(None),
):
    uid = _bearer_uid(authorization)

    # Server-computed, not trusted from the client — this is the number that
    # actually gets persisted as the session's result.
    ending_value = sum(
        body.finalCounts.get(color, 0) * value
        for color, value in body.denominations.items()
    )
    profit_loss = ending_value - body.buyIn
    photo_url = _session_photo_urls.get(f"{uid}:{session_id}", "")

    save_session(
        uid,
        session_id,
        {
            "buyIn": body.buyIn,
            "denominations": body.denominations,
            "finalCounts": body.finalCounts,
            "elapsedSeconds": body.elapsedSeconds,
            "endingValue": ending_value,
            "profitLoss": profit_loss,
            "photoUrl": photo_url,
        },
    )

    logger.info("session=%s uid=%s profitLoss=%.2f", session_id, uid, profit_loss)
    return CompleteSessionResponse(profitLoss=profit_loss, photoUrl=photo_url)
