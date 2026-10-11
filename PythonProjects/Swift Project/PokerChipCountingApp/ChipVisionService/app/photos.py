"""
Photo intake: size/format validation and metadata stripping.

Chip photos are taken at home games, so they can include faces, the venue,
and — straight off a camera — GPS coordinates in EXIF. Nothing downstream needs
any of that, so every upload is decoded and re-encoded from pixels only;
OpenCV's encoder writes no EXIF/XMP/ICC segments, which is what strips them.
(`cv2.imdecode` has already applied any EXIF rotation by then, so detection
sees the same upright image it always did.)
"""

import os
from typing import Tuple

import cv2
import numpy as np

MAX_UPLOAD_BYTES = int(os.environ.get("MAX_UPLOAD_BYTES", 10 * 1024 * 1024))
# A tiny file can declare enormous dimensions; refuse to hold the decoded
# pixels for anything past a ~50 MP sensor.
MAX_IMAGE_PIXELS = int(os.environ.get("MAX_IMAGE_PIXELS", 50_000_000))
STORED_JPEG_QUALITY = 90


class ImageRejected(Exception):
    """An upload the service refuses; carries the HTTP status to return."""

    def __init__(self, status_code: int, detail: str):
        super().__init__(detail)
        self.status_code = status_code
        self.detail = detail


def decode_and_sanitize(raw_bytes: bytes) -> Tuple[np.ndarray, bytes]:
    """Returns (decoded BGR image for detection, metadata-free JPEG to store)."""
    if not raw_bytes:
        raise ImageRejected(400, "Empty image upload")
    if len(raw_bytes) > MAX_UPLOAD_BYTES:
        raise ImageRejected(
            413, f"Image is larger than {MAX_UPLOAD_BYTES // (1024 * 1024)} MB"
        )

    image_bgr = cv2.imdecode(np.frombuffer(raw_bytes, dtype=np.uint8), cv2.IMREAD_COLOR)
    if image_bgr is None:
        raise ImageRejected(400, "Could not decode image")

    height, width = image_bgr.shape[:2]
    if height * width > MAX_IMAGE_PIXELS:
        raise ImageRejected(413, "Image resolution is too large")

    ok, encoded = cv2.imencode(
        ".jpg", image_bgr, [int(cv2.IMWRITE_JPEG_QUALITY), STORED_JPEG_QUALITY]
    )
    if not ok:
        raise ImageRejected(500, "Could not process image")
    return image_bgr, encoded.tobytes()
