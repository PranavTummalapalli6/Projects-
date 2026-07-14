"""
All Firebase access for this service lives here: verifying the app's Firebase
Auth ID tokens, uploading chip photos to Storage, and writing completed session
records to Firestore. The iOS app never talks to Storage/Firestore directly —
only through this backend, using the Admin SDK's full-access credentials. That
keeps the "who can write what" decision in code that's tested here, rather than
in Firebase security rules deployed separately.
"""

import logging
import os
from datetime import datetime, timezone
from typing import Dict, Optional

import firebase_admin
from fastapi import HTTPException, status
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials, firestore, storage

logger = logging.getLogger("chip-vision-service")

_app: Optional[firebase_admin.App] = None

_DEFAULT_BUCKET = "pokerchipapp-f7a84.firebasestorage.app"


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

    try:
        if cred_path and os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
            _app = firebase_admin.initialize_app(cred, {"storageBucket": bucket})
        else:
            # On Cloud Run with a service account attached to the revision, this
            # picks up Application Default Credentials with no key file needed.
            _app = firebase_admin.initialize_app(options={"storageBucket": bucket})
    except Exception:
        logger.exception(
            "Firebase did not initialize (no valid credentials found). "
            "Endpoints that need Firebase will return errors until "
            "GOOGLE_APPLICATION_CREDENTIALS points at a real service-account key."
        )


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


def upload_photo(uid: str, session_id: str, jpeg_bytes: bytes) -> str:
    """Uploads the chip photo and returns its public URL.

    NOTE: `make_public()` is the simplest option to get the app a usable URL
    without also shipping Storage security rules from this session. For a
    production app where these photos shouldn't be publicly link-accessible,
    swap this for `blob.generate_signed_url(...)` with a private bucket instead.
    """
    bucket = storage.bucket()
    blob = bucket.blob(f"chip-photos/{uid}/{session_id}.jpg")
    blob.upload_from_string(jpeg_bytes, content_type="image/jpeg")
    blob.make_public()
    return blob.public_url


def save_session(uid: str, session_id: str, data: Dict) -> None:
    db = firestore.client()
    doc_ref = (
        db.collection("sessions")
        .document(uid)
        .collection("games")
        .document(session_id)
    )
    doc_ref.set({**data, "createdAt": datetime.now(timezone.utc).isoformat()})
