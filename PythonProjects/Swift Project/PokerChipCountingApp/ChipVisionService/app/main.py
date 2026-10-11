import asyncio
import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Annotated, Optional

from fastapi import FastAPI, File, Form, Header, HTTPException, Path, Query, Request, Response, UploadFile, status
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from app.chip_detection import detect_chips_detailed
from app.firebase import (
    delete_account_data,
    delete_night,
    delete_night_photos,
    delete_session,
    firebase_ready,
    get_weekly_summary,
    import_legacy_nights,
    init_firebase,
    list_nights,
    photo_exists,
    photo_path,
    PHOTO_URL_TTL_SECONDS,
    put_night,
    save_photo_ref,
    save_session,
    signed_photo_url,
    upload_photo,
    verify_token,
)
from app.logging_config import configure_logging, uid_tag
from app.models import (
    ChipDetectionResponse,
    CompleteSessionRequest,
    CompleteSessionResponse,
    DetectionModel,
    ImportLegacyResponse,
    NightPage,
    PhotoUrlResponse,
    PutNightResponse,
    StackModel,
    WeeklySummaryResponse,
)
from app import nights, photos
from app.photos import ImageRejected, decode_and_sanitize
from app.ratelimit import SlidingWindowLimiter
from app.side_view import CameraPose, detect_stacks

configure_logging()
logger = logging.getLogger("chip-vision-service")

# Photo analysis is the one expensive call (OpenCV on every request).
_photo_limiter = SlidingWindowLimiter(
    limit=int(os.environ.get("PHOTO_RATE_LIMIT_PER_HOUR", 60)),
    window_seconds=3600,
)

# Syncing nights is cheap, but a stuck client shouldn't be able to write forever.
_night_limiter = SlidingWindowLimiter(
    limit=int(os.environ.get("NIGHT_WRITE_RATE_LIMIT_PER_HOUR", 600)),
    window_seconds=3600,
)

# Session ids end up in Firestore document ids and Storage object names, so
# only the characters a UUID uses (plus underscore) are accepted — no slashes
# or dots that could reach outside the caller's own folder.
SessionId = Annotated[str, Path(pattern=r"^[A-Za-z0-9_-]{1,64}$")]

# Night ids are UUIDs (the app makes them), in either letter case.
NightId = Annotated[
    str,
    Path(pattern=r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"),
]


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_firebase()
    yield


app = FastAPI(title="ChipVisionService", lifespan=lifespan)


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    """Unlike /healthz (process is up), reports whether Firebase initialized —
    the signal a load balancer should use before sending real traffic."""
    if firebase_ready():
        return {"status": "ready"}
    return JSONResponse(status_code=503, content={"status": "firebase-unavailable"})


def _bearer_uid(authorization: Optional[str]) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing 'Authorization: Bearer <token>' header",
        )
    token = authorization.removeprefix("Bearer ").strip()
    return verify_token(token)


def _cents(amount: float) -> int:
    return int(round(amount * 100))


def _utc_iso(moment: datetime) -> str:
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(timezone.utc).isoformat(timespec="microseconds")


@app.post("/v1/sessions/{session_id}/photo", response_model=ChipDetectionResponse)
async def analyze_photo(
    session_id: SessionId,
    image: UploadFile = File(...),
    denominations: str = Form(...),
    # How the chips were photographed. "top" is the original circle counter; "side"
    # reads piles from the side or a low angle, and uses the camera's pose if sent.
    view: str = Form("top"),
    pitch: Optional[float] = Form(None, ge=-30, le=90),
    roll: Optional[float] = Form(None, ge=-180, le=180),
    focal35: Optional[float] = Form(None, ge=8, le=200),
    # The chip colours in play, comma separated.
    colors: Optional[str] = Form(None, max_length=100),
    authorization: Optional[str] = Header(None),
):
    uid = _bearer_uid(authorization)
    if view not in ("top", "side"):
        raise HTTPException(status_code=400, detail="view must be 'top' or 'side'")

    if not _photo_limiter.allow(uid):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many photo analyses — please try again in a little while",
        )

    try:
        parsed = json.loads(denominations)
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="denominations must be valid JSON")
    if not isinstance(parsed, dict):
        raise HTTPException(status_code=400, detail="denominations must be a JSON object")

    # Read one byte past the limit so an oversized upload is detected without
    # ever buffering all of it. The limit is photos.MAX_UPLOAD_BYTES — the same
    # value decode_and_sanitize enforces, read at call time so there is only one.
    raw_bytes = await image.read(photos.MAX_UPLOAD_BYTES + 1)
    try:
        image_bgr, clean_jpeg = await asyncio.to_thread(decode_and_sanitize, raw_bytes)
    except ImageRejected as rejected:
        raise HTTPException(status_code=rejected.status_code, detail=rejected.detail)

    # detect_chips is CPU-bound (OpenCV, no I/O) — running it inline here would
    # block the whole event loop for the duration of the Hough transform.
    stacks: list = []
    detections: list = []
    if view == "side":
        pose = CameraPose(pitch, roll or 0.0, focal35 or 24.0) if pitch is not None else None
        in_play = [c.strip().title() for c in colors.split(",") if c.strip()] if colors else None
        counts, confidence, stacks = await asyncio.to_thread(detect_stacks, image_bgr, pose, in_play)
    else:
        counts, confidence, detections = await asyncio.to_thread(detect_chips_detailed, image_bgr)

    # Storing the photo is a convenience: if Storage is down the user still
    # gets their counts, just without a stored copy.
    photo_url = ""
    try:
        path = await asyncio.to_thread(upload_photo, uid, session_id, clean_jpeg)
        await asyncio.to_thread(save_photo_ref, uid, session_id, path)
        photo_url = await asyncio.to_thread(signed_photo_url, path)
    except Exception:  # noqa: BLE001
        logger.exception("Could not store the chip photo", extra={"fields": {"uid": uid_tag(uid)}})

    logger.info(
        "photo_analyzed",
        extra={"fields": {
            "uid": uid_tag(uid),
            "session": session_id,
            "confidence": confidence,
            "view": view,
            "chips": sum(counts.values()),
            "stored": bool(photo_url),
        }},
    )
    return ChipDetectionResponse(
        counts=counts,
        confidence=confidence,
        photoUrl=photo_url,
        detections=[DetectionModel(x=d.x, y=d.y, r=d.r, color=d.color) for d in detections],
        stacks=[StackModel(**vars(stack)) for stack in stacks],
        view=view,
    )


@app.post("/v1/sessions/{session_id}/complete", response_model=CompleteSessionResponse)
async def complete_session(
    session_id: SessionId,
    body: CompleteSessionRequest,
    authorization: Optional[str] = Header(None),
):
    uid = _bearer_uid(authorization)

    # Server-computed, not trusted from the client — this is the number that
    # actually gets persisted as the session's result. Done in integer cents so
    # the stored result can never carry float noise like 27.500000000000004.
    buy_in_cents = _cents(body.buyIn)
    ending_cents = sum(
        body.finalCounts.get(color, 0) * _cents(value)
        for color, value in body.denominations.items()
    )
    profit_cents = ending_cents - buy_in_cents

    record = {
        "buyIn": buy_in_cents / 100,
        "buyInCents": buy_in_cents,
        "denominations": body.denominations,
        "finalCounts": body.finalCounts,
        "elapsedSeconds": body.elapsedSeconds,
        "endingValue": ending_cents / 100,
        "endingValueCents": ending_cents,
        "profitLoss": profit_cents / 100,
        "profitLossCents": profit_cents,
    }
    if body.startedAt is not None:
        record["startedAt"] = _utc_iso(body.startedAt)
    if body.tzIdentifier:
        record["tzIdentifier"] = body.tzIdentifier
    if body.sessionGroupId:
        record["sessionGroupId"] = body.sessionGroupId

    stored = await asyncio.to_thread(save_session, uid, session_id, record)

    stored_photo = stored.get("photoPath")
    photo_url = await asyncio.to_thread(signed_photo_url, stored_photo) if stored_photo else ""

    logger.info(
        "session_completed",
        extra={"fields": {
            "uid": uid_tag(uid),
            "session": session_id,
            "profitLossCents": profit_cents,
            "elapsedSeconds": body.elapsedSeconds,
        }},
    )
    return CompleteSessionResponse(
        profitLoss=profit_cents / 100, profitLossCents=profit_cents, photoUrl=photo_url
    )


# Declared before any "/v1/sessions/{session_id}" route could shadow it.
@app.get("/v1/sessions/weekly-summary", response_model=WeeklySummaryResponse)
async def weekly_summary(
    tz: Optional[str] = Query(default=None, max_length=64),
    authorization: Optional[str] = Header(None),
):
    uid = _bearer_uid(authorization)
    # get_weekly_summary does blocking Firestore calls, same as detect_chips
    # above — offload it so it doesn't block the event loop.
    summary = await asyncio.to_thread(get_weekly_summary, uid, tz)
    return WeeklySummaryResponse(**summary)


@app.get("/v1/sessions/{session_id}/photo-url", response_model=PhotoUrlResponse)
async def session_photo_url(
    session_id: SessionId,
    authorization: Optional[str] = Header(None),
):
    uid = _bearer_uid(authorization)
    # The path is derived from the caller's own uid, so a session id can only
    # ever resolve to an object in their own folder.
    path = photo_path(uid, session_id)
    if not await asyncio.to_thread(photo_exists, path):
        raise HTTPException(status_code=404, detail="No photo stored for this session")
    url = await asyncio.to_thread(signed_photo_url, path)
    if not url:
        raise HTTPException(status_code=503, detail="Could not create a photo link right now")
    return PhotoUrlResponse(photoUrl=url, expiresInSeconds=PHOTO_URL_TTL_SECONDS)


@app.delete("/v1/sessions/{session_id}", status_code=204)
async def remove_session(
    session_id: SessionId,
    authorization: Optional[str] = Header(None),
):
    uid = _bearer_uid(authorization)
    await asyncio.to_thread(delete_session, uid, session_id)
    return Response(status_code=204)


# ------------------------------------------------------------------ nights

async def _read_limited_body(request: Request, limit: int) -> bytes:
    """The request body, refusing anything bigger than `limit` without reading all of it."""
    declared = request.headers.get("content-length")
    if declared and declared.isdigit() and int(declared) > limit:
        raise HTTPException(status_code=413, detail="That night is too large to save")
    chunks, size = [], 0
    async for chunk in request.stream():
        size += len(chunk)
        if size > limit:
            raise HTTPException(status_code=413, detail="That night is too large to save")
        chunks.append(chunk)
    return b"".join(chunks)


def _night_write_allowed(uid: str) -> None:
    if not _night_limiter.allow(uid):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many changes in a short time — please try again in a little while",
        )


@app.put("/v1/nights/{night_id}", response_model=PutNightResponse)
async def put_night_endpoint(
    night_id: NightId,
    request: Request,
    authorization: Optional[str] = Header(None),
):
    """Saves one night. Idempotent and last-writer-wins by the night's own
    `updatedAt` (see app/nights.py): re-sending a version is harmless, and if the
    server already holds a later edit it answers `applied: false` with that edit."""
    uid = _bearer_uid(authorization)
    _night_write_allowed(uid)

    raw = await _read_limited_body(request, nights.MAX_BODY_BYTES)
    try:
        night = nights.NightModel.model_validate_json(raw)
    except ValidationError as error:
        raise HTTPException(status_code=422, detail=nights.describe(error))
    if night.id != night_id.upper():
        raise HTTPException(status_code=400, detail="The night's id doesn't match the address it was sent to")

    stored, applied, previous = await asyncio.to_thread(put_night, uid, nights.stored_form(night))

    # Deleting a night also removes the chip photos kept for it.
    if applied and night.deletedAt is not None:
        player_ids = {player.id for player in night.players}
        player_ids.update(player.get("id", "") for player in (previous or {}).get("players", []) if player.get("id"))
        await asyncio.to_thread(delete_night_photos, uid, night.id, sorted(player_ids))

    logger.info(
        "night_synced",
        extra={"fields": {
            "uid": uid_tag(uid),
            "applied": applied,
            "players": len(night.players),
            "deleted": bool(night.deletedAt),
        }},
    )
    return PutNightResponse(
        night=nights.public_form(stored), applied=applied, serverUpdatedAt=stored["serverUpdatedAt"]
    )


@app.get("/v1/nights", response_model=NightPage)
async def list_nights_endpoint(
    since: Optional[str] = Query(default=None, max_length=48),
    limit: int = Query(default=100, ge=1, le=200),
    authorization: Optional[str] = Header(None),
):
    """Nights (and tombstones) changed after the cursor `since`, oldest change first."""
    uid = _bearer_uid(authorization)
    cursor_in = None
    if since:
        try:
            cursor_in = nights.normalize_cursor(since)
        except ValueError as error:
            raise HTTPException(status_code=400, detail=str(error))
    rows, cursor, has_more = await asyncio.to_thread(list_nights, uid, cursor_in, limit)
    return NightPage(nights=rows, cursor=cursor, hasMore=has_more)


# Declared before the "{night_id}" routes it could be mistaken for.
@app.post("/v1/nights/import-legacy", response_model=ImportLegacyResponse)
async def import_legacy_endpoint(authorization: Optional[str] = Header(None)):
    """Turns the account's old single-player sessions into one-player nights. Safe
    to call any number of times."""
    uid = _bearer_uid(authorization)
    _night_write_allowed(uid)
    imported = await asyncio.to_thread(import_legacy_nights, uid)
    logger.info("legacy_nights_imported", extra={"fields": {"uid": uid_tag(uid), "imported": imported}})
    return ImportLegacyResponse(imported=imported)


@app.delete("/v1/nights/{night_id}", status_code=204)
async def remove_night(night_id: NightId, authorization: Optional[str] = Header(None)):
    """Deletes a night, leaving only the marker other devices need (no names, place or notes)."""
    uid = _bearer_uid(authorization)
    _night_write_allowed(uid)
    deleted = await asyncio.to_thread(delete_night, uid, night_id.upper())
    if deleted is None:
        raise HTTPException(status_code=404, detail="No such night")
    _, player_ids = deleted
    await asyncio.to_thread(delete_night_photos, uid, night_id.upper(), player_ids)
    return Response(status_code=204)


@app.delete("/v1/account", status_code=204)
async def remove_account(authorization: Optional[str] = Header(None)):
    """Deletes the caller's account and everything stored for it. Required for
    App Store review: an app that lets people create an account must let them
    delete it from inside the app."""
    uid = _bearer_uid(authorization)
    await asyncio.to_thread(delete_account_data, uid)
    logger.info("account_deleted", extra={"fields": {"uid": uid_tag(uid)}})
    return Response(status_code=204)
