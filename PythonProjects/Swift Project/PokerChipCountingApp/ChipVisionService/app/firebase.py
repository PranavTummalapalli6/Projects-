"""
All Firebase access for this service lives here: verifying the app's Firebase
Auth ID tokens, storing chip photos, and reading/writing session records. The
iOS app never talks to Storage/Firestore directly — only through this backend,
using the Admin SDK's full-access credentials — so the checked-in security
rules (see firestore.rules / storage.rules at the repo root) deny every direct
client request, and "who can read or write what" is decided in tested code here.

Photos are stored as *private* objects. Callers get a short-lived signed URL
on demand (`signed_photo_url`); nothing is ever made publicly readable.
"""

import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Dict, Iterable, List, Optional, Tuple

import firebase_admin
from fastapi import HTTPException, status
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials, firestore, storage
from google.api_core.exceptions import AlreadyExists
from google.cloud.firestore_v1.base_query import FieldFilter

from app import nights
from app.weekly import resolve_timezone, summarize_week, window_start_utc

logger = logging.getLogger("chip-vision-service")

_app: Optional[firebase_admin.App] = None

_DEFAULT_BUCKET = "pokerchipapp-f7a84.firebasestorage.app"
PHOTO_PREFIX = "chip-photos"
PHOTO_URL_TTL_SECONDS = int(os.environ.get("PHOTO_URL_TTL_SECONDS", 3600))


def firebase_ready() -> bool:
    return _app is not None


def init_firebase() -> None:
    """Best-effort init at startup. Deliberately non-fatal: a missing/invalid
    credential shouldn't take down the whole process (so /healthz stays up) —
    it should only fail the specific request that actually needs Firebase.
    """
    global _app
    if _app is not None:
        return

    bucket = os.environ.get("FIREBASE_STORAGE_BUCKET", _DEFAULT_BUCKET)
    cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")

    app = None
    try:
        if cred_path and os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
            app = firebase_admin.initialize_app(cred, {"storageBucket": bucket})
        else:
            # On Cloud Run with a service account attached to the revision, this
            # picks up Application Default Credentials with no key file needed.
            app = firebase_admin.initialize_app(options={"storageBucket": bucket})
            # initialize_app() doesn't go looking for those credentials until the
            # first call that needs them, so without this /readyz would say
            # "ready" on an instance that can't actually reach Firebase.
            app.credential.get_credential()
        _app = app
    except Exception:
        logger.exception(
            "Firebase did not initialize (no valid credentials found). "
            "Endpoints that need Firebase will return errors until "
            "GOOGLE_APPLICATION_CREDENTIALS points at a real service-account key."
        )
        if app is not None:
            # Unregister the half-started app so a later attempt can start clean.
            try:
                firebase_admin.delete_app(app)
            except Exception:  # noqa: BLE001 — nothing more to do if cleanup fails
                logger.debug("Could not remove the half-initialized Firebase app", exc_info=True)


def verify_token(id_token: str) -> str:
    """Returns the caller's Firebase uid, or raises HTTP 401."""
    try:
        decoded = firebase_auth.verify_id_token(id_token)
        return decoded["uid"]
    except Exception as exc:  # noqa: BLE001 — any verification failure is an auth failure
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid or expired auth token: {exc}",
        )


def _now_iso() -> str:
    # Fixed-width (always includes microseconds) so these strings sort
    # chronologically and compare correctly in Firestore range queries.
    return datetime.now(timezone.utc).isoformat(timespec="microseconds")


def _game_ref(uid: str, session_id: str):
    return (
        firestore.client()
        .collection("sessions")
        .document(uid)
        .collection("games")
        .document(session_id)
    )


# ---------------------------------------------------------------- photos

def photo_path(uid: str, session_id: str) -> str:
    return f"{PHOTO_PREFIX}/{uid}/{session_id}.jpg"


def upload_photo(uid: str, session_id: str, jpeg_bytes: bytes) -> str:
    """Stores the (already metadata-stripped) photo as a private object and
    returns its storage path — not a URL."""
    blob = storage.bucket().blob(photo_path(uid, session_id))
    blob.upload_from_string(jpeg_bytes, content_type="image/jpeg")
    return blob.name


_signing_credentials = None


def _signing_kwargs() -> Dict:
    """Extra args `generate_signed_url` needs when the process has no private
    key — i.e. Cloud Run using its attached service identity, which signs via
    the IAM API instead. With a key file (local Docker) the credentials can
    sign directly, so this returns nothing. Credentials are looked up once and
    only refreshed when their token has expired, not on every request."""
    global _signing_credentials
    try:
        import google.auth
        from google.auth.transport import requests as google_requests

        if _signing_credentials is None:
            _signing_credentials, _ = google.auth.default()
        creds = _signing_credentials
        if hasattr(creds, "sign_bytes"):
            return {}
        if not creds.valid:
            creds.refresh(google_requests.Request())
        return {
            "service_account_email": creds.service_account_email,
            "access_token": creds.token,
        }
    except Exception:  # noqa: BLE001 — fall back to default signing
        return {}


def signed_photo_url(path: str, ttl_seconds: Optional[int] = None) -> str:
    """A time-limited read URL for a stored photo, or "" if one can't be made
    (the photo is a convenience, never a reason to fail a request)."""
    ttl = ttl_seconds or PHOTO_URL_TTL_SECONDS
    try:
        blob = storage.bucket().blob(path)
        return blob.generate_signed_url(
            version="v4",
            expiration=timedelta(seconds=ttl),
            method="GET",
            **_signing_kwargs(),
        )
    except Exception:  # noqa: BLE001
        logger.exception("Could not sign a photo URL")
        return ""


def photo_exists(path: str) -> bool:
    try:
        return bool(storage.bucket().blob(path).exists())
    except Exception:  # noqa: BLE001
        logger.exception("Could not check for a stored photo")
        return False


def save_photo_ref(uid: str, session_id: str, path: str) -> None:
    """Remembers which object belongs to a session, durably, so /complete can
    attach it even after a restart or on a different instance. The doc is
    marked `pending` until the session is completed."""
    _game_ref(uid, session_id).set(
        {"photoPath": path, "photoUploadedAt": _now_iso(), "status": "pending"},
        merge=True,
    )


# -------------------------------------------------------------- sessions

def save_session(uid: str, session_id: str, data: Dict) -> Dict:
    """Writes the completed session and returns the stored document.

    Idempotent: completing the same session twice (the app lets people edit
    counts and resubmit) rewrites the result but keeps the original
    `createdAt` and any attached `photoPath`.
    """
    ref = _game_ref(uid, session_id)
    snapshot = ref.get()
    existing = snapshot.to_dict() if snapshot.exists else {}
    now = _now_iso()

    payload = {
        **data,
        "status": "complete",
        "createdAt": existing.get("createdAt") or now,
        "updatedAt": now,
    }
    ref.set(payload, merge=True)
    return {**existing, **payload}


def delete_session(uid: str, session_id: str) -> bool:
    """Deletes one session and its photo. Returns False if it didn't exist."""
    ref = _game_ref(uid, session_id)
    snapshot = ref.get()
    existing = snapshot.to_dict() if snapshot.exists else {}

    path = existing.get("photoPath") or photo_path(uid, session_id)
    try:
        blob = storage.bucket().blob(path)
        if blob.exists():
            blob.delete()
    except Exception:  # noqa: BLE001 — don't leave the record behind over a missing file
        logger.exception("Could not delete a session photo")

    if snapshot.exists:
        ref.delete()
    return bool(snapshot.exists)


def delete_account_data(uid: str) -> None:
    """Removes everything stored for a user: all session records, every photo
    under their prefix, and finally the Firebase Auth account itself. Each
    step is safe to repeat, so a half-finished deletion can simply be retried."""
    db = firestore.client()
    db.recursive_delete(db.collection("sessions").document(uid))

    for blob in storage.bucket().list_blobs(prefix=f"{PHOTO_PREFIX}/{uid}/"):
        blob.delete()

    try:
        firebase_auth.delete_user(uid)
    except firebase_auth.UserNotFoundError:
        pass


# ---------------------------------------------------------------- nights

def _nights_collection(uid: str):
    return (
        firestore.client()
        .collection("sessions")
        .document(uid)
        .collection("nights")
    )


def night_photo_sessions(night_id: str, player_ids: Iterable[str]) -> List[str]:
    """The session ids the app uses for a night's cash-out photos: the night's id
    and the first eight characters of the player's. (Photos are stored under
    these, by the same endpoint as every other chip photo.)"""
    return [f"{night_id}-{player_id[:8]}" for player_id in player_ids]


def delete_night_photos(uid: str, night_id: str, player_ids: Iterable[str]) -> int:
    """Removes the chip photos taken at a night's cash-outs, and the records that
    point at them. Returns how many photos existed. Called when a night is deleted,
    so deleting it really does remove what was kept for it."""
    removed = 0
    for session_id in night_photo_sessions(night_id, player_ids):
        try:
            if delete_session(uid, session_id):
                removed += 1
        except Exception:  # noqa: BLE001 — one bad object must not leave the rest behind
            logger.exception("Could not delete a night's photo")
    return removed


def put_night(uid: str, document: Dict) -> Tuple[Dict, bool, Optional[Dict]]:
    """Stores a night (already validated, in stored form) unless the server holds
    a later edit of it. Returns the version the server now holds, whether that
    is the one offered, and what was held before (None if nothing). Runs in a
    transaction, so two devices writing at once can't overwrite each other's
    newer edit.
    """
    ref = _nights_collection(uid).document(document["id"])

    @firestore.transactional
    def attempt(transaction):
        snapshot = ref.get(transaction=transaction)
        existing = snapshot.to_dict() if snapshot.exists else None
        decision = nights.decide_put(existing, document)
        if not decision.write:
            return existing, decision.applied, existing
        stored = {**document, "serverUpdatedAt": _now_iso()}
        transaction.set(ref, stored)
        return stored, True, existing

    return attempt(firestore.client().transaction())


def list_nights(uid: str, since: Optional[str], limit: int) -> Tuple[List[Dict], Optional[str], bool]:
    """Nights changed after `since` (a cursor from an earlier call), oldest change
    first. Tombstones are included so other devices learn of deletions. Returns the
    nights, the cursor to continue from, and whether more are waiting."""
    query = _nights_collection(uid)
    if since:
        query = query.where(filter=FieldFilter("serverUpdatedAt", ">", since))
    query = query.order_by("serverUpdatedAt").limit(limit + 1)
    rows = [snapshot.to_dict() or {} for snapshot in query.stream()]
    has_more = len(rows) > limit
    rows = rows[:limit]
    cursor = rows[-1]["serverUpdatedAt"] if rows else since
    return [nights.public_form(row) for row in rows], cursor, has_more


def delete_night(uid: str, night_id: str) -> Optional[Tuple[Dict, List[str]]]:
    """Turns a night into a tombstone. Returns it with the ids of the players it
    had, or None if the server never had that night. Deleting twice is harmless."""
    ref = _nights_collection(uid).document(night_id)

    @firestore.transactional
    def attempt(transaction):
        snapshot = ref.get(transaction=transaction)
        if not snapshot.exists:
            return None
        existing = snapshot.to_dict() or {}
        players = [player.get("id", "") for player in existing.get("players", []) if player.get("id")]
        if existing.get("deletedAt"):
            return existing, players
        now = datetime.now(timezone.utc)
        # Strictly later than the version being deleted, whatever the clocks say.
        updated = max(now, nights.parse_instant(existing["updatedAt"]) + timedelta(milliseconds=1))
        tombstone = nights.tombstone_of({
            **existing,
            "updatedAt": nights.format_instant(updated),
            "deletedAt": nights.format_instant(now),
        })
        stored = {**tombstone, "serverUpdatedAt": _now_iso()}
        transaction.set(ref, stored)
        return stored, players

    return attempt(firestore.client().transaction())


def import_legacy_nights(uid: str) -> int:
    """Turns the account's old single-player sessions into one-player nights.
    Safe to run any number of times: an imported night's id comes from the old
    session's id, and an existing night (imported earlier, or since edited) is
    never overwritten. Returns how many were added."""
    games = firestore.client().collection("sessions").document(uid).collection("games")
    added = 0
    for snapshot in games.stream():
        night = nights.legacy_night(uid, snapshot.id, snapshot.to_dict() or {})
        if night is None:
            continue
        ref = _nights_collection(uid).document(night["id"])
        try:
            ref.create({**night, "serverUpdatedAt": _now_iso()})
            added += 1
        except AlreadyExists:
            continue
    return added


# --------------------------------------------------------------- summary

def get_weekly_summary(uid: str, tz_name: Optional[str] = None) -> Dict:
    """Total playtime and a per-day breakdown for the last 7 local days, for
    the "Poker Health" dashboard (see app/weekly.py for the bucketing rules).

    `createdAt` is an ISO 8601 UTC string, not a Firestore Timestamp; being
    fixed-width and always UTC, string order matches chronological order, so
    it works in a range query. It's the completion time, which can never
    precede the start — so "completed on or after the window began" safely
    over-selects, and the exact local-day check happens in `summarize_week`.
    """
    tz = resolve_timezone(tz_name)
    now = datetime.now(timezone.utc)
    lower_bound = window_start_utc(now, tz).isoformat(timespec="microseconds")

    games = (
        firestore.client().collection("sessions").document(uid).collection("games")
    )
    query = games.where(filter=FieldFilter("createdAt", ">=", lower_bound))
    return summarize_week((doc.to_dict() or {} for doc in query.stream()), tz, now)
