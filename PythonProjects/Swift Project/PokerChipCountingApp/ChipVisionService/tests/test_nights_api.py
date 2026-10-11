"""Syncing nights over HTTP, against in-memory stand-ins for Firestore: the app's
whole promise about its data — safe to retry, never loses a newer edit, keeps
users apart, and leaves nothing of a deleted night but a marker."""

import copy
import json
import types
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

import app.firebase as fb
import app.main as main
from app import nights
from app.ratelimit import SlidingWindowLimiter
from tests.fakes import FakeBucket, FakeFirestore

ALICE = {"Authorization": "Bearer alice"}
BOB = {"Authorization": "Bearer bob"}
NIGHT_ID = "11111111-2222-3333-4444-555555555555"
OTHER_ID = "99999999-2222-3333-4444-555555555555"
SAM = "AAAAAAAA-2222-3333-4444-555555555555"


@pytest.fixture
def cloud(monkeypatch):
    db, bucket, deleted_users = FakeFirestore(), FakeBucket(), []
    monkeypatch.setattr(fb.firestore, "client", lambda: db)
    monkeypatch.setattr(fb.firestore, "transactional", lambda function: function)
    monkeypatch.setattr(fb.storage, "bucket", lambda: bucket)
    monkeypatch.setattr(fb.firebase_auth, "delete_user", lambda uid: deleted_users.append(uid))
    monkeypatch.setattr(main, "verify_token", lambda token: {"alice": "u1", "bob": "u2"}[token])

    # Every write gets its own, later server timestamp, as it would in real life.
    ticks = iter(range(1, 10_000))
    base = datetime(2026, 8, 7, tzinfo=timezone.utc)
    monkeypatch.setattr(fb, "_now_iso", lambda: (base + timedelta(microseconds=next(ticks))).isoformat(timespec="microseconds"))
    return types.SimpleNamespace(db=db, bucket=bucket, deleted_users=deleted_users)


@pytest.fixture
def client(cloud):
    return TestClient(main.app)


def make_night(night_id=NIGHT_ID, updated="2026-08-06T19:00:00.000Z", **overrides):
    night = {
        "schemaVersion": 1,
        "id": night_id,
        "startedAt": "2026-08-06T19:00:00.000Z",
        "tzIdentifier": "America/Los_Angeles",
        "currency": "USD",
        "defaultBuyInMinor": 2500,
        "location": "Pat's garage",
        "colors": ["White", "Red"],
        "denominationsMinor": {"White": 25, "Red": 100},
        "players": [{
            "id": SAM,
            "name": "Sam",
            "buyIns": [{"id": "CCCCCCCC-2222-3333-4444-555555555555", "amountMinor": 2500, "at": "2026-08-06T19:00:00.000Z"}],
        }],
        "pauses": [],
        "updatedAt": updated,
    }
    night.update(overrides)
    return night


def put(client, night, headers=ALICE, night_id=None):
    return client.put(f"/v1/nights/{night_id or night['id']}", json=night, headers=headers)


def stored_nights(cloud, uid="u1"):
    prefix = f"sessions/{uid}/nights/"
    return {path[len(prefix):]: doc for path, doc in cloud.db.docs.items() if path.startswith(prefix)}


# ------------------------------------------------------------------------ auth

@pytest.mark.parametrize("method, path", [
    ("put", f"/v1/nights/{NIGHT_ID}"),
    ("get", "/v1/nights"),
    ("delete", f"/v1/nights/{NIGHT_ID}"),
    ("post", "/v1/nights/import-legacy"),
])
def test_every_night_endpoint_needs_a_signed_in_user(client, method, path):
    assert getattr(client, method)(path).status_code == 401


# ------------------------------------------------------------------------ PUT

def test_a_new_night_is_stored_and_echoed_with_the_servers_timestamp(client, cloud):
    response = put(client, make_night())
    assert response.status_code == 200
    body = response.json()
    assert body["applied"] is True
    assert body["night"]["id"] == NIGHT_ID
    assert body["night"]["players"][0]["name"] == "Sam"
    assert "serverUpdatedAt" not in body["night"]
    assert body["serverUpdatedAt"].startswith("2026-08-07T00:00:00.")

    document = stored_nights(cloud)[NIGHT_ID]
    assert document["serverUpdatedAt"] == body["serverUpdatedAt"]
    assert document["location"] == "Pat's garage"


def test_sending_the_same_night_again_succeeds_without_writing_again(client, cloud):
    first = put(client, make_night()).json()
    second = put(client, make_night()).json()
    assert second["applied"] is True
    assert second["serverUpdatedAt"] == first["serverUpdatedAt"], "a retry must not move the sync cursor"
    assert len(stored_nights(cloud)) == 1


def test_a_later_edit_replaces_the_night_and_moves_the_cursor(client, cloud):
    first = put(client, make_night()).json()
    edited = make_night(updated="2026-08-06T20:00:00.000Z", notes="Pat won")
    second = put(client, edited).json()
    assert second["applied"] is True
    assert second["night"]["notes"] == "Pat won"
    assert second["serverUpdatedAt"] > first["serverUpdatedAt"]


def test_an_earlier_edit_cannot_overwrite_a_later_one_and_gets_the_later_one_back(client, cloud):
    put(client, make_night(updated="2026-08-06T20:00:00.000Z", notes="newer"))
    stale = put(client, make_night(updated="2026-08-06T19:30:00.000Z", notes="older")).json()
    assert stale["applied"] is False
    assert stale["night"]["notes"] == "newer"
    assert stored_nights(cloud)[NIGHT_ID]["notes"] == "newer"


def test_a_tie_between_two_devices_keeps_the_first_and_tells_the_second(client, cloud):
    put(client, make_night(notes="phone"))
    second = put(client, make_night(notes="ipad")).json()
    assert second["applied"] is False
    assert second["night"]["notes"] == "phone"


def test_the_id_in_the_address_may_be_in_either_case(client):
    assert put(client, make_night(), night_id=NIGHT_ID.lower()).status_code == 200


def test_the_id_in_the_address_must_match_the_night(client):
    response = put(client, make_night(), night_id=OTHER_ID)
    assert response.status_code == 400


def test_a_malformed_night_is_refused_without_echoing_who_played(client, cloud):
    night = make_night()
    night["players"][0]["name"] = "Margaret Hamilton " * 5      # too long
    response = put(client, night)
    assert response.status_code == 422
    assert "players.0.name" in response.json()["detail"]
    assert "Margaret" not in response.text
    assert stored_nights(cloud) == {}


def test_a_newer_app_sending_fields_this_server_does_not_know_is_told_so(client, cloud):
    response = put(client, make_night(handicap=3))
    assert response.status_code == 422
    assert "handicap" in response.json()["detail"]
    assert stored_nights(cloud) == {}


def test_a_night_that_is_not_json_is_refused(client):
    response = client.put(f"/v1/nights/{NIGHT_ID}", content=b"{ not json", headers={**ALICE, "Content-Type": "application/json"})
    assert response.status_code == 422


def test_an_enormous_upload_is_refused_before_it_is_parsed(client, cloud):
    body = json.dumps(make_night(notes="x" * (nights.MAX_BODY_BYTES + 10)))
    response = client.put(f"/v1/nights/{NIGHT_ID}", content=body, headers={**ALICE, "Content-Type": "application/json"})
    assert response.status_code == 413
    assert stored_nights(cloud) == {}


def test_a_night_id_that_is_not_a_uuid_is_refused(client):
    assert client.put("/v1/nights/../../account", json=make_night(), headers=ALICE).status_code in (404, 422)
    assert client.put("/v1/nights/not-a-uuid", json=make_night(), headers=ALICE).status_code == 422


def test_each_person_has_their_own_nights(client, cloud):
    put(client, make_night(notes="alice's"), ALICE)
    put(client, make_night(notes="bob's"), BOB)
    assert stored_nights(cloud, "u1")[NIGHT_ID]["notes"] == "alice's"
    assert stored_nights(cloud, "u2")[NIGHT_ID]["notes"] == "bob's"
    assert [n["notes"] for n in client.get("/v1/nights", headers=BOB).json()["nights"]] == ["bob's"]


# ------------------------------------------------------------------ deletion

def test_a_deleted_night_is_stored_as_a_marker_with_no_trace_of_who_played(client, cloud):
    put(client, make_night())
    deleted = make_night(updated="2026-08-06T21:00:00.000Z", deletedAt="2026-08-06T21:00:00.000Z", notes="Pat won")
    response = put(client, deleted).json()

    assert response["applied"] is True
    for place in (response["night"], stored_nights(cloud)[NIGHT_ID]):
        text = json.dumps(place)
        assert "Sam" not in text and "garage" not in text and "Pat won" not in text
    assert response["night"]["deletedAt"] == "2026-08-06T21:00:00.000Z"
    assert response["night"]["players"] == []
    nights.NightModel.model_validate(response["night"])           # still a valid night for the app to read


def test_an_undo_after_a_deletion_brings_the_night_back(client):
    put(client, make_night())
    put(client, make_night(updated="2026-08-06T21:00:00.000Z", deletedAt="2026-08-06T21:00:00.000Z"))
    undone = put(client, make_night(updated="2026-08-06T21:00:30.000Z")).json()
    assert undone["applied"] is True
    assert undone["night"]["players"][0]["name"] == "Sam"
    assert "deletedAt" not in undone["night"]


def test_a_stale_edit_cannot_resurrect_a_night_deleted_after_it(client):
    put(client, make_night(updated="2026-08-06T21:00:00.000Z", deletedAt="2026-08-06T21:00:00.000Z"))
    stale = put(client, make_night(updated="2026-08-06T20:00:00.000Z")).json()
    assert stale["applied"] is False
    assert stale["night"]["deletedAt"] == "2026-08-06T21:00:00.000Z"


def test_the_delete_endpoint_leaves_a_marker_that_sorts_after_the_night(client, cloud):
    created = put(client, make_night(updated="2026-08-06T19:00:00.000Z")).json()
    assert client.delete(f"/v1/nights/{NIGHT_ID}", headers=ALICE).status_code == 204

    document = stored_nights(cloud)[NIGHT_ID]
    assert document["players"] == [] and "location" not in document
    assert document["updatedAt"] > "2026-08-06T19:00:00.000Z"
    assert document["serverUpdatedAt"] > created["serverUpdatedAt"], "other devices will see the change"
    assert client.delete(f"/v1/nights/{NIGHT_ID}", headers=ALICE).status_code == 204, "deleting twice is harmless"


def test_deleting_a_night_the_server_never_had_is_a_404(client):
    assert client.delete(f"/v1/nights/{NIGHT_ID}", headers=ALICE).status_code == 404


def test_one_person_cannot_delete_anothers_night(client, cloud):
    put(client, make_night(), ALICE)
    assert client.delete(f"/v1/nights/{NIGHT_ID}", headers=BOB).status_code == 404
    assert stored_nights(cloud, "u1")[NIGHT_ID]["players"], "still intact"


# ----------------------------------------------------------------------- GET

def test_an_empty_history_is_an_empty_page(client):
    body = client.get("/v1/nights", headers=ALICE).json()
    assert body == {"nights": [], "cursor": None, "hasMore": False}


def test_everything_comes_back_oldest_change_first_including_deletions(client):
    for index in range(3):
        put(client, make_night(night_id=f"0000000{index}-2222-3333-4444-555555555555", notes=f"n{index}"))
    put(client, make_night(night_id="00000001-2222-3333-4444-555555555555", updated="2026-08-06T22:00:00.000Z",
                           deletedAt="2026-08-06T22:00:00.000Z"))

    body = client.get("/v1/nights", headers=ALICE).json()
    assert [n["id"][:8] for n in body["nights"]] == ["00000000", "00000002", "00000001"], "ordered by when the server last changed them"
    assert body["nights"][-1]["deletedAt"] == "2026-08-06T22:00:00.000Z"
    assert body["hasMore"] is False
    assert all("serverUpdatedAt" not in n for n in body["nights"])


def test_pages_chain_through_the_cursor_with_nothing_missed_or_repeated(client):
    ids = [f"0000000{index}-2222-3333-4444-555555555555" for index in range(5)]
    for night_id in ids:
        put(client, make_night(night_id=night_id))

    seen, cursor = [], None
    for _ in range(10):
        params = {"limit": 2, **({"since": cursor} if cursor else {})}
        page = client.get("/v1/nights", params=params, headers=ALICE).json()
        seen += [n["id"] for n in page["nights"]]
        cursor = page["cursor"]
        if not page["hasMore"]:
            break
    assert seen == ids

    again = client.get("/v1/nights", params={"since": cursor}, headers=ALICE).json()
    assert again["nights"] == [] and again["cursor"] == cursor and again["hasMore"] is False


def test_only_what_changed_since_the_cursor_is_returned(client):
    put(client, make_night(night_id="00000000-2222-3333-4444-555555555555"))
    cursor = client.get("/v1/nights", headers=ALICE).json()["cursor"]
    put(client, make_night(night_id="00000001-2222-3333-4444-555555555555"))
    put(client, make_night(night_id="00000000-2222-3333-4444-555555555555", updated="2026-08-06T20:00:00.000Z", notes="edited"))

    page = client.get("/v1/nights", params={"since": cursor}, headers=ALICE).json()
    assert [(n["id"][:8], n.get("notes")) for n in page["nights"]] == [("00000001", None), ("00000000", "edited")]


def test_a_cursor_in_any_iso_form_is_understood(client):
    put(client, make_night())
    cursor = client.get("/v1/nights", headers=ALICE).json()["cursor"]
    assert client.get("/v1/nights", params={"since": cursor.replace("+00:00", "Z")}, headers=ALICE).json()["nights"] == []


@pytest.mark.parametrize("params, status", [
    ({"since": "yesterday"}, 400),
    ({"since": "2026-08-06T19:00:00"}, 400),
    ({"limit": 0}, 422),
    ({"limit": 201}, 422),
])
def test_a_bad_query_is_refused(client, params, status):
    assert client.get("/v1/nights", params=params, headers=ALICE).status_code == status


# --------------------------------------------------------------- legacy import

def seed_games(cloud):
    games = {
        "s1": {"status": "complete", "buyInCents": 2500, "endingValueCents": 4500, "elapsedSeconds": 3600,
               "denominations": {"White": 0.25, "Red": 0.5}, "startedAt": "2026-08-01T19:00:00.000000+00:00",
               "createdAt": "2026-08-01T20:00:00.000000+00:00", "updatedAt": "2026-08-01T20:00:00.000000+00:00"},
        "s2": {"status": "complete", "buyInCents": 1000, "endingValueCents": 0, "elapsedSeconds": 1800,
               "denominations": {"White": 0.25}, "createdAt": "2026-08-02T20:00:00.000000+00:00"},
        "abandoned": {"status": "pending", "photoPath": "chip-photos/u1/abandoned.jpg"},
        "broken": {"status": "complete", "buyInCents": "lots"},
    }
    for session_id, record in games.items():
        cloud.db.collection("sessions").document("u1").collection("games").document(session_id).set(record)
    cloud.db.collection("sessions").document("u2").collection("games").document("theirs").set(games["s1"])


def test_old_sessions_become_nights_once_and_only_complete_ones(client, cloud):
    seed_games(cloud)

    first = client.post("/v1/nights/import-legacy", headers=ALICE)
    assert first.status_code == 200 and first.json() == {"imported": 2}
    assert client.post("/v1/nights/import-legacy", headers=ALICE).json() == {"imported": 0}

    page = client.get("/v1/nights", headers=ALICE).json()
    assert len(page["nights"]) == 2
    assert {n["source"] for n in page["nights"]} == {"legacy-session"}
    assert sorted(n["players"][0]["cashOutMinor"] for n in page["nights"]) == [0, 4500]
    assert stored_nights(cloud, "u2") == {}, "another account's sessions are not touched"


def test_importing_never_overwrites_a_night_that_has_since_been_edited(client, cloud):
    seed_games(cloud)
    client.post("/v1/nights/import-legacy", headers=ALICE)
    imported = client.get("/v1/nights", headers=ALICE).json()["nights"][0]

    edited = copy.deepcopy(imported)
    edited["updatedAt"] = "2026-09-01T00:00:00.000Z"
    edited["notes"] = "fixed the buy-in"
    assert put(client, edited).json()["applied"] is True

    assert client.post("/v1/nights/import-legacy", headers=ALICE).json() == {"imported": 0}
    assert stored_nights(cloud)[imported["id"]]["notes"] == "fixed the buy-in"


# ------------------------------------------------------- limits and deletion

def test_a_stuck_client_is_slowed_down_but_reading_stays_open(client, monkeypatch):
    monkeypatch.setattr(main, "_night_limiter", SlidingWindowLimiter(limit=2, window_seconds=3600))
    assert put(client, make_night()).status_code == 200
    assert put(client, make_night()).status_code == 200
    assert put(client, make_night()).status_code == 429
    assert client.get("/v1/nights", headers=ALICE).status_code == 200


def test_deleting_the_account_deletes_its_nights_and_only_its_nights(client, cloud):
    put(client, make_night(), ALICE)
    put(client, make_night(), BOB)
    assert client.delete("/v1/account", headers=ALICE).status_code == 204
    assert stored_nights(cloud, "u1") == {}
    assert NIGHT_ID in stored_nights(cloud, "u2")


# ------------------------------------------------------------ photos go with the night

def photo_key(night_id=NIGHT_ID, player_id=SAM, uid="u1"):
    return f"chip-photos/{uid}/{night_id}-{player_id[:8]}.jpg"


def seed_photo(cloud, night_id=NIGHT_ID, player_id=SAM, uid="u1"):
    fb.save_photo_ref(uid, f"{night_id}-{player_id[:8]}", fb.upload_photo(uid, f"{night_id}-{player_id[:8]}", b"jpeg"))


def test_deleting_a_night_removes_the_photos_kept_for_it_and_no_others(client, cloud):
    put(client, make_night())
    seed_photo(cloud)
    seed_photo(cloud, night_id=OTHER_ID)                       # another night's photo
    assert photo_key() in cloud.bucket.objects

    deleted = make_night(updated="2026-08-06T21:00:00.000Z", deletedAt="2026-08-06T21:00:00.000Z")
    assert put(client, deleted).json()["applied"] is True

    assert photo_key() not in cloud.bucket.objects
    assert photo_key(night_id=OTHER_ID) in cloud.bucket.objects
    assert f"sessions/u1/games/{NIGHT_ID}-{SAM[:8]}" not in cloud.db.docs, "and the record that pointed at it"


def test_the_delete_endpoint_removes_them_too(client, cloud):
    put(client, make_night())
    seed_photo(cloud)
    assert client.delete(f"/v1/nights/{NIGHT_ID}", headers=ALICE).status_code == 204
    assert photo_key() not in cloud.bucket.objects


def test_a_player_added_on_another_phone_has_their_photo_removed_as_well(client, cloud):
    late = "FFFFFFFF-2222-3333-4444-555555555555"
    both = make_night()
    both["players"].append({
        "id": late, "name": "Kim",
        "buyIns": [{"id": "EEEEEEEE-2222-3333-4444-555555555555", "amountMinor": 2500, "at": "2026-08-06T19:00:00.000Z"}],
    })
    put(client, both)
    seed_photo(cloud, player_id=late)

    # The phone that deletes it never heard about Kim.
    assert put(client, make_night(updated="2026-08-06T21:00:00.000Z", deletedAt="2026-08-06T21:00:00.000Z")).json()["applied"] is True
    assert photo_key(player_id=late) not in cloud.bucket.objects


def test_a_stale_deletion_that_loses_to_a_later_edit_removes_nothing(client, cloud):
    put(client, make_night(updated="2026-08-06T22:00:00.000Z"))
    seed_photo(cloud)
    stale = put(client, make_night(updated="2026-08-06T21:00:00.000Z", deletedAt="2026-08-06T21:00:00.000Z")).json()
    assert stale["applied"] is False
    assert photo_key() in cloud.bucket.objects
