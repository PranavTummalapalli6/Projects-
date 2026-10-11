import types
from datetime import datetime, timezone

import pytest

import app.firebase as fb
from tests.fakes import FakeBucket, FakeFirestore

FROZEN = datetime(2026, 8, 6, 12, 0, tzinfo=timezone.utc)


@pytest.fixture
def cloud(monkeypatch):
    """The real app/firebase.py functions running against in-memory fakes."""
    db, bucket, deleted_users = FakeFirestore(), FakeBucket(), []
    monkeypatch.setattr(fb.firestore, "client", lambda: db)
    monkeypatch.setattr(fb.storage, "bucket", lambda: bucket)
    monkeypatch.setattr(fb, "_signing_kwargs", lambda: {})
    monkeypatch.setattr(fb.firebase_auth, "delete_user", lambda uid: deleted_users.append(uid))
    return types.SimpleNamespace(db=db, bucket=bucket, deleted_users=deleted_users)


@pytest.fixture
def frozen_now(monkeypatch):
    class Frozen(datetime):
        @classmethod
        def now(cls, tz=None):
            return FROZEN.astimezone(tz) if tz else FROZEN.replace(tzinfo=None)

    monkeypatch.setattr(fb, "datetime", Frozen)


def test_photos_are_stored_privately_and_returned_as_a_path_not_a_url(cloud):
    path = fb.upload_photo("u1", "s1", b"jpeg-bytes")

    assert path == "chip-photos/u1/s1.jpg"
    assert cloud.bucket.objects[path] == (b"jpeg-bytes", "image/jpeg")
    # FakeBlob has no make_public()/public_url — reaching for either would have
    # raised AttributeError above. The photo is private by construction.


def test_signed_urls_are_time_limited(cloud):
    url = fb.signed_photo_url("chip-photos/u1/s1.jpg", ttl_seconds=900)
    assert "ttl=900" in url and "method=GET" in url


def test_a_failure_to_sign_returns_empty_instead_of_failing_the_request(cloud, monkeypatch):
    def broken_bucket():
        raise RuntimeError("storage is down")

    monkeypatch.setattr(fb.storage, "bucket", broken_bucket)
    assert fb.signed_photo_url("chip-photos/u1/s1.jpg") == ""


def test_save_session_is_idempotent_and_keeps_created_at_and_the_photo(cloud):
    fb.save_photo_ref("u1", "s1", "chip-photos/u1/s1.jpg")

    first = fb.save_session("u1", "s1", {"profitLoss": 5.0, "elapsedSeconds": 600})
    second = fb.save_session("u1", "s1", {"profitLoss": 7.5, "elapsedSeconds": 600})

    assert second["createdAt"] == first["createdAt"]
    assert second["profitLoss"] == 7.5
    assert second["photoPath"] == "chip-photos/u1/s1.jpg"
    assert second["status"] == "complete"
    assert len(cloud.db.docs) == 1  # re-completing rewrote the record, didn't add one


def test_abandoned_sessions_with_only_a_photo_never_reach_the_weekly_summary(cloud, frozen_now):
    fb.save_photo_ref("u1", "abandoned", "chip-photos/u1/abandoned.jpg")
    assert fb.get_weekly_summary("u1", "UTC")["totalSeconds"] == 0


def test_delete_session_removes_the_record_and_its_photo(cloud):
    path = fb.upload_photo("u1", "s1", b"x")
    fb.save_photo_ref("u1", "s1", path)
    fb.save_session("u1", "s1", {"elapsedSeconds": 60})

    assert fb.delete_session("u1", "s1") is True
    assert cloud.db.docs == {}
    assert cloud.bucket.objects == {}


def test_deleting_an_unknown_session_is_a_harmless_no_op(cloud):
    assert fb.delete_session("u1", "nope") is False


def test_delete_account_removes_every_record_photo_and_the_auth_user(cloud):
    for session in ("a", "b"):
        path = fb.upload_photo("u1", session, b"x")
        fb.save_photo_ref("u1", session, path)
        fb.save_session("u1", session, {"elapsedSeconds": 60})
    other = fb.upload_photo("u2", "keep", b"x")
    fb.save_session("u2", "keep", {"elapsedSeconds": 60})

    fb.delete_account_data("u1")

    assert not any(path.startswith("sessions/u1") for path in cloud.db.docs)
    assert not any(name.startswith("chip-photos/u1/") for name in cloud.bucket.objects)
    assert cloud.deleted_users == ["u1"]
    # Another user's data is untouched.
    assert "sessions/u2/games/keep" in cloud.db.docs
    assert other in cloud.bucket.objects


def test_delete_account_can_be_retried_after_the_auth_user_is_already_gone(cloud, monkeypatch):
    def gone(uid):
        raise fb.firebase_auth.UserNotFoundError("already deleted")

    monkeypatch.setattr(fb.firebase_auth, "delete_user", gone)
    fb.delete_account_data("u1")  # must not raise


# ------------------------------------------------------------ initialization

class _FakeApp:
    def __init__(self, credential_error=None):
        self.credential = types.SimpleNamespace(get_credential=self._get_credential)
        self._credential_error = credential_error

    def _get_credential(self):
        if self._credential_error:
            raise self._credential_error
        return object()


@pytest.fixture
def uninitialized(monkeypatch):
    removed = []
    monkeypatch.setattr(fb, "_app", None)
    monkeypatch.delenv("GOOGLE_APPLICATION_CREDENTIALS", raising=False)
    monkeypatch.setattr(fb.firebase_admin, "delete_app", removed.append)
    return removed


def test_the_service_is_ready_once_default_credentials_resolve(monkeypatch, uninitialized):
    app = _FakeApp()
    monkeypatch.setattr(fb.firebase_admin, "initialize_app", lambda *a, **k: app)

    fb.init_firebase()

    assert fb.firebase_ready()
    assert uninitialized == []


def test_the_service_is_not_ready_when_no_credentials_can_be_found(monkeypatch, uninitialized):
    # initialize_app() itself succeeds without credentials and only fails on
    # first use — readiness has to look for them up front.
    app = _FakeApp(credential_error=RuntimeError("no default credentials"))
    monkeypatch.setattr(fb.firebase_admin, "initialize_app", lambda *a, **k: app)

    fb.init_firebase()

    assert not fb.firebase_ready()
    # The half-started app is removed so a later attempt can initialize cleanly.
    assert uninitialized == [app]


def test_a_failed_start_can_be_retried(monkeypatch, uninitialized):
    broken, working = _FakeApp(credential_error=RuntimeError("nope")), _FakeApp()
    apps = iter([broken, working])
    monkeypatch.setattr(fb.firebase_admin, "initialize_app", lambda *a, **k: next(apps))

    fb.init_firebase()
    assert not fb.firebase_ready()
    fb.init_firebase()
    assert fb.firebase_ready()
