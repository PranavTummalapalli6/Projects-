import cv2
import numpy as np
import pytest

from app import photos
from app.photos import ImageRejected, decode_and_sanitize


def _chip_image(width: int = 160, height: int = 120) -> np.ndarray:
    image = np.full((height, width, 3), (170, 175, 170), dtype=np.uint8)
    cv2.circle(image, (width // 2, height // 2), 30, (40, 40, 210), -1)
    return image


def _jpeg_with_fake_gps_exif(image: np.ndarray) -> bytes:
    """A real JPEG with an extra APP1 'Exif' segment spliced in right after
    SOI, carrying GPS-looking text — what a camera photo's metadata looks like
    to anything that copies bytes verbatim."""
    ok, encoded = cv2.imencode(".jpg", image)
    assert ok
    data = encoded.tobytes()
    payload = (
        b"Exif\x00\x00"
        b"MM\x00*\x00\x00\x00\x08"
        b"GPSLatitude=37.7749;GPSLongitude=-122.4194"
    )
    app1 = b"\xff\xe1" + (len(payload) + 2).to_bytes(2, "big") + payload
    return data[:2] + app1 + data[2:]


def _segment_markers(jpeg: bytes) -> list:
    """The marker types before the image data starts (SOS), e.g. 0xE1 = APP1."""
    assert jpeg[:2] == b"\xff\xd8", "not a JPEG"
    markers, i = [], 2
    while i < len(jpeg):
        assert jpeg[i] == 0xFF
        marker = jpeg[i + 1]
        markers.append(marker)
        if marker == 0xDA:
            break
        i += 2 + int.from_bytes(jpeg[i + 2 : i + 4], "big")
    return markers


def test_metadata_is_stripped_before_a_photo_is_stored():
    original = _jpeg_with_fake_gps_exif(_chip_image())
    assert b"GPSLatitude" in original and 0xE1 in _segment_markers(original)

    _, stored = decode_and_sanitize(original)

    assert b"GPSLatitude" not in stored
    assert b"Exif" not in stored
    markers = _segment_markers(stored)
    for forbidden in (0xE1, 0xE2, 0xED, 0xFE):  # EXIF/XMP, ICC, Photoshop/IPTC, comment
        assert forbidden not in markers


def test_sanitized_photo_keeps_the_pixels_and_dimensions():
    image = _chip_image(200, 140)
    decoded, stored = decode_and_sanitize(_jpeg_with_fake_gps_exif(image))

    assert decoded.shape == (140, 200, 3)
    round_trip = cv2.imdecode(np.frombuffer(stored, dtype=np.uint8), cv2.IMREAD_COLOR)
    assert round_trip.shape == (140, 200, 3)
    # Lossy JPEG, but the red chip should still be clearly red in the centre.
    b, g, r = (int(v) for v in round_trip[70, 100])
    assert r > 150 and b < 90


def test_empty_upload_is_rejected():
    with pytest.raises(ImageRejected) as error:
        decode_and_sanitize(b"")
    assert error.value.status_code == 400


def test_non_image_bytes_are_rejected():
    with pytest.raises(ImageRejected) as error:
        decode_and_sanitize(b"definitely not a jpeg" * 100)
    assert error.value.status_code == 400


def test_oversized_upload_is_rejected(monkeypatch):
    monkeypatch.setattr(photos, "MAX_UPLOAD_BYTES", 1000)
    with pytest.raises(ImageRejected) as error:
        decode_and_sanitize(b"\xff\xd8" + b"0" * 2000)
    assert error.value.status_code == 413


def test_absurd_resolution_is_rejected(monkeypatch):
    monkeypatch.setattr(photos, "MAX_IMAGE_PIXELS", 1000)
    ok, encoded = cv2.imencode(".jpg", _chip_image(160, 120))
    assert ok
    with pytest.raises(ImageRejected) as error:
        decode_and_sanitize(encoded.tobytes())
    assert error.value.status_code == 413
