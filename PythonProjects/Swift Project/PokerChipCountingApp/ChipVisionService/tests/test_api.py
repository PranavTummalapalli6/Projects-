import types
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import cv2
import numpy as np
import pytest
from fastapi.testclient import TestClient

import app.firebase as fb
import app.main as main
import app.photos as photos
from app.chip_detection import Detection
from app.ratelimit import SlidingWindowLimiter
from app.side_view import Stack
from tests.fakes import FakeBucket, FakeFirestore

FROZEN = datetime(2026, 8, 6, 12, 0, tzinfo=timezone.utc)
AUTH = {"Authorization": "Bearer test-token"}
SESSION = "11111111-2222-3333-4444-555555555555"


@pytest.fixture
def cloud(monkeypatch):
    db, bucket, deleted_users = FakeFirestore(), FakeBucket(), []
    monkeypatch.setattr(fb.firestore, "client", lambda: db)
    monkeypatch.setattr(fb.storage, "bucket", lambda: bucket)
    monkeypatch.setattr(fb, "_signing_kwargs", lambda: {})
    monkeypatch.setattr(fb.firebase_auth, "delete_user", lambda uid: deleted_users.append(uid))
    monkeypatch.setattr(main, "verify_token", lambda token: "u1")
    monkeypatch.setattr(
        main,
        "detect_chips_detailed",
        lambda image: (
            {"White": 3, "Red": 2},
            "high",
            [Detection(0.25, 0.4, 0.05, "White")] * 3 + [Detection(0.7, 0.55, 0.05, "Red")] * 2,
        ),
    )
    return types.SimpleNamespace(db=db, bucket=bucket, deleted_users=deleted_users)


@pytest.fixture
def frozen_now(monkeypatch):
    class Frozen(datetime):
        @classmethod
        def now(cls, tz=None):
            return FROZEN.astimezone(tz) if tz else FROZEN.replace(tzinfo=None)

    monkeypatch.setattr(fb, "datetime", Frozen)


@pytest.fixture
def client(cloud):
    return TestClient(main.app)


def _jpeg_bytes() -> bytes:
    image = np.full((90, 120, 3), (170, 175, 170), dtype=np.uint8)
    cv2.circle(image, (60, 45), 20, (40, 40, 210), -1)
    ok, encoded = cv2.imencode(".jpg", image)
    assert ok
    data = encoded.tobytes()
    payload = b"Exif\x00\x00GPSLatitude=37.7749"
    app1 = b"\xff\xe1" + (len(payload) + 2).to_bytes(2, "big") + payload
    return data[:2] + app1 + data[2:]


def _upload(client, session=SESSION, body=None, headers=AUTH, denominations="{}", **fields):
    return client.post(
        f"/v1/sessions/{session}/photo",
        files={"image": ("chips.jpg", body if body is not None else _jpeg_bytes(), "image/jpeg")},
        data={"denominations": denominations, **fields},
        headers=headers,
    )


def _complete_payload(**overrides):
    payload = {
        "buyIn": 25,
        "denominations": {"White": 0.25, "Red": 0.5},
        "finalCounts": {"White": 40, "Red": 30},
        "elapsedSeconds": 3600,
    }
    payload.update(overrides)
    return payload


# -------------------------------------------------------------- health / auth

def test_health_and_readiness(client, monkeypatch):
    assert client.get("/healthz").json() == {"status": "ok"}
    monkeypatch.setattr(main, "firebase_ready", lambda: False)
    assert client.get("/readyz").status_code == 503
    monkeypatch.setattr(main, "firebase_ready", lambda: True)
    assert client.get("/readyz").status_code == 200


@pytest.mark.parametrize("method, path", [
    ("get", "/v1/sessions/weekly-summary"),
    ("delete", "/v1/account"),
    ("delete", f"/v1/sessions/{SESSION}"),
    ("get", f"/v1/sessions/{SESSION}/photo-url"),
])
def test_protected_endpoints_require_a_bearer_token(client, method, path):
    assert getattr(client, method)(path).status_code == 401


def test_session_ids_cannot_reach_outside_the_callers_own_folder(client):
    for bad in ("..%2F..%2Fother", "a b", "x" * 65, "has.dot"):
        assert client.delete(f"/v1/sessions/{bad}", headers=AUTH).status_code in (404, 422), bad


# -------------------------------------------------------------------- photo

def test_photo_upload_returns_counts_and_stores_a_private_metadata_free_copy(client, cloud):
    response = _upload(client)

    assert response.status_code == 200
    body = response.json()
    assert body["counts"] == {"White": 3, "Red": 2}
    # Where each chip is, so the app can draw them on the photo for correction.
    assert len(body["detections"]) == 5
    assert body["detections"][0] == {"x": 0.25, "y": 0.4, "r": 0.05, "color": "White"}
    assert body["confidence"] == "high"
    assert body["photoUrl"].startswith("https://signed.example/chip-photos/u1/")

    stored, content_type = cloud.bucket.objects[f"chip-photos/u1/{SESSION}.jpg"]
    assert content_type == "image/jpeg"
    assert b"GPSLatitude" not in stored and b"Exif" not in stored

    pending = cloud.db.docs[f"sessions/u1/games/{SESSION}"]
    assert pending["photoPath"] == f"chip-photos/u1/{SESSION}.jpg"
    assert pending["status"] == "pending"


def test_a_photo_taken_from_the_side_is_read_as_piles_with_the_cameras_pose(client, monkeypatch):
    seen = {}

    def piles(image, pose, colors):
        seen.update(pose=pose, colors=colors)
        return {"Red": 2, "Green": 5}, "low", [
            Stack(0.3, 0.5, 0.12, 0.08, -2.0, "Red", 2, "low"),
            Stack(0.6, 0.5, 0.12, 0.2, -2.0, "Green", 5, "low"),
        ]

    monkeypatch.setattr(main, "detect_stacks", piles)
    response = _upload(client, view="side", pitch="16.5", roll="2.0", focal35="24", colors="red, GREEN")

    assert response.status_code == 200
    body = response.json()
    assert body["view"] == "side"
    assert body["counts"] == {"Red": 2, "Green": 5}
    assert body["detections"] == []
    assert body["stacks"][1] == {"x": 0.6, "y": 0.5, "w": 0.12, "h": 0.2, "angle": -2.0, "color": "Green", "count": 5, "confidence": "low"}
    assert (seen["pose"].pitch_deg, seen["pose"].roll_deg, seen["pose"].focal_35mm) == (16.5, 2.0, 24.0)
    assert seen["colors"] == ["Red", "Green"]


def test_a_side_photo_without_a_pose_is_still_read(client, monkeypatch):
    seen = {}
    monkeypatch.setattr(main, "detect_stacks", lambda image, pose, colors: seen.update(pose=pose, colors=colors) or ({}, "low", []))

    assert _upload(client, view="side").status_code == 200
    assert seen == {"pose": None, "colors": None}


def test_the_photo_view_defaults_to_the_original_circle_counter(client):
    body = _upload(client).json()
    assert body["view"] == "top" and body["stacks"] == []


def test_an_unknown_view_or_an_impossible_pose_is_refused(client):
    assert _upload(client, view="sideways").status_code == 400
    assert _upload(client, view="side", pitch="200").status_code == 422
    assert _upload(client, view="side", pitch="10", roll="400").status_code == 422
    assert _upload(client, view="side", pitch="10", focal35="1").status_code == 422


def test_a_storage_outage_does_not_cost_the_user_their_counts(client, monkeypatch):
    def broken(*args, **kwargs):
        raise RuntimeError("storage is down")

    monkeypatch.setattr(main, "upload_photo", broken)
    response = _upload(client)

    assert response.status_code == 200
    assert response.json()["counts"] == {"White": 3, "Red": 2}
    assert response.json()["photoUrl"] == ""


def test_bad_uploads_are_rejected_with_clear_statuses(client, monkeypatch):
    assert _upload(client, body=b"not an image").status_code == 400
    assert _upload(client, denominations="not json").status_code == 400
    assert _upload(client, denominations="[1,2]").status_code == 400

    monkeypatch.setattr(photos, "MAX_UPLOAD_BYTES", 500)
    assert _upload(client, body=b"\xff\xd8" + b"0" * 2000).status_code == 413


def test_photo_analysis_is_rate_limited_per_user(client, monkeypatch):
    monkeypatch.setattr(main, "_photo_limiter", SlidingWindowLimiter(2, 3600))
    assert _upload(client).status_code == 200
    assert _upload(client).status_code == 200
    assert _upload(client).status_code == 429


def test_photo_links_are_only_issued_for_the_callers_own_existing_photo(client, cloud):
    assert client.get(f"/v1/sessions/{SESSION}/photo-url", headers=AUTH).status_code == 404

    _upload(client)
    response = client.get(f"/v1/sessions/{SESSION}/photo-url", headers=AUTH)

    assert response.status_code == 200
    assert response.json()["photoUrl"].startswith("https://signed.example/chip-photos/u1/")
    assert response.json()["expiresInSeconds"] == fb.PHOTO_URL_TTL_SECONDS


# ----------------------------------------------------------------- complete

def test_complete_computes_the_result_in_exact_cents(client, cloud):
    # 0.1 + 0.2 style float noise must not leak into a stored result.
    payload = _complete_payload(
        buyIn=0.35,
        denominations={"White": 0.05, "Red": 0.1},
        finalCounts={"White": 3, "Red": 2},
    )
    response = client.post(f"/v1/sessions/{SESSION}/complete", json=payload, headers=AUTH)

    assert response.status_code == 200
    assert response.json() == {"profitLoss": 0.0, "profitLossCents": 0, "photoUrl": ""}
    doc = cloud.db.docs[f"sessions/u1/games/{SESSION}"]
    assert doc["endingValueCents"] == 35 and doc["buyInCents"] == 35
    assert doc["endingValue"] == 0.35


def test_completing_twice_is_idempotent_and_keeps_the_photo_attached(client, cloud):
    _upload(client)
    first = client.post(f"/v1/sessions/{SESSION}/complete", json=_complete_payload(), headers=AUTH)
    created = cloud.db.docs[f"sessions/u1/games/{SESSION}"]["createdAt"]

    edited = _complete_payload(finalCounts={"White": 50, "Red": 30})
    second = client.post(f"/v1/sessions/{SESSION}/complete", json=edited, headers=AUTH)

    assert first.status_code == second.status_code == 200
    assert second.json()["photoUrl"].startswith("https://signed.example/")
    assert second.json()["profitLossCents"] == 50 * 25 + 30 * 50 - 2500
    assert len([p for p in cloud.db.docs if p.startswith("sessions/u1/games/")]) == 1
    assert cloud.db.docs[f"sessions/u1/games/{SESSION}"]["createdAt"] == created


def test_complete_stores_timing_fields_in_utc(client, cloud):
    payload = _complete_payload(
        startedAt="2026-08-05T19:00:00-07:00",
        tzIdentifier="America/Los_Angeles",
        sessionGroupId="night-1",
    )
    assert client.post(f"/v1/sessions/{SESSION}/complete", json=payload, headers=AUTH).status_code == 200

    doc = cloud.db.docs[f"sessions/u1/games/{SESSION}"]
    assert doc["startedAt"].startswith("2026-08-06T02:00:00")
    assert doc["tzIdentifier"] == "America/Los_Angeles"
    assert doc["sessionGroupId"] == "night-1"


@pytest.mark.parametrize("override", [
    {"buyIn": 0},
    {"buyIn": -5},
    {"elapsedSeconds": -1},
    {"finalCounts": {"White": -3}},
    {"denominations": {"White": 0}},
])
def test_complete_rejects_nonsense_values(client, override):
    response = client.post(f"/v1/sessions/{SESSION}/complete", json=_complete_payload(**override), headers=AUTH)
    assert response.status_code == 422


def test_older_app_builds_that_omit_the_new_fields_still_work(client):
    assert client.post(f"/v1/sessions/{SESSION}/complete", json=_complete_payload(), headers=AUTH).status_code == 200


# ----------------------------------------------------- weekly summary (E2E)

def _local_iso(year, month, day, hour, minute, tz_name):
    return datetime(year, month, day, hour, minute, tzinfo=ZoneInfo(tz_name)).isoformat()


@pytest.mark.parametrize("tz_name, segments", [
    # A night of rebuys, the last starting at 23:30 local and running past midnight.
    ("America/Los_Angeles", [(19, 0, 60), (20, 0, 30), (23, 30, 45)]),
    ("Asia/Kolkata", [(20, 0, 60), (21, 0, 30), (23, 30, 45)]),
])
def test_a_three_segment_rebuy_night_reports_135_minutes_and_the_bars_add_up(
    client, cloud, frozen_now, tz_name, segments
):
    for index, (hour, minute, minutes) in enumerate(segments):
        payload = _complete_payload(
            # The app sends this segment's own time, never the running total.
            elapsedSeconds=minutes * 60,
            startedAt=_local_iso(2026, 8, 5, hour, minute, tz_name),
            tzIdentifier=tz_name,
            sessionGroupId="night-1",
        )
        response = client.post(f"/v1/sessions/segment-{index}/complete", json=payload, headers=AUTH)
        assert response.status_code == 200

    summary = client.get("/v1/sessions/weekly-summary", params={"tz": tz_name}, headers=AUTH).json()

    assert summary["totalSeconds"] == 135 * 60
    bars = {day["date"]: day["seconds"] for day in summary["days"]}
    assert bars["2026-08-05"] == 135 * 60
    assert sum(bars.values()) == summary["totalSeconds"]
    assert len(summary["days"]) == 7


# ------------------------------------------------------------------ deletion

def test_deleting_a_session_removes_it_and_is_repeatable(client, cloud):
    _upload(client)
    client.post(f"/v1/sessions/{SESSION}/complete", json=_complete_payload(), headers=AUTH)

    assert client.delete(f"/v1/sessions/{SESSION}", headers=AUTH).status_code == 204
    assert cloud.db.docs == {} and cloud.bucket.objects == {}
    assert client.delete(f"/v1/sessions/{SESSION}", headers=AUTH).status_code == 204


def test_deleting_the_account_removes_everything_stored_for_the_user(client, cloud):
    _upload(client)
    client.post(f"/v1/sessions/{SESSION}/complete", json=_complete_payload(), headers=AUTH)

    assert client.delete("/v1/account", headers=AUTH).status_code == 204

    assert not [p for p in cloud.db.docs if p.startswith("sessions/u1")]
    assert cloud.bucket.objects == {}
    assert cloud.deleted_users == ["u1"]
