"""The rules for synced nights, without any HTTP or Firestore: what is accepted,
the one canonical form it is stored in, what a deleted night keeps, whose edit
wins, and how an old single-player session becomes a night."""

import copy
import json
import random

import pytest
from pydantic import ValidationError

from app import nights

NIGHT_ID = "11111111-2222-3333-4444-555555555555"
SAM = "AAAAAAAA-2222-3333-4444-555555555555"
ALEX = "BBBBBBBB-2222-3333-4444-555555555555"


def make_night(**overrides):
    night = {
        "schemaVersion": 1,
        "id": NIGHT_ID,
        "startedAt": "2026-08-06T19:00:00.000Z",
        "tzIdentifier": "America/Los_Angeles",
        "currency": "USD",
        "defaultBuyInMinor": 2500,
        "location": "Pat's garage",
        "notes": "Rain delay",
        "colors": ["White", "Red"],
        "denominationsMinor": {"White": 25, "Red": 100},
        "players": [
            {
                "id": SAM,
                "name": "Sam",
                "buyIns": [{"id": "CCCCCCCC-2222-3333-4444-555555555555", "amountMinor": 2500, "at": "2026-08-06T19:00:00.000Z"}],
            },
            {
                "id": ALEX,
                "name": "Alex",
                "buyIns": [{"id": "DDDDDDDD-2222-3333-4444-555555555555", "amountMinor": 2500, "at": "2026-08-06T19:00:00.000Z"}],
            },
        ],
        "pauses": [],
        "updatedAt": "2026-08-06T19:00:00.000Z",
    }
    night.update(overrides)
    return night


def stored(**overrides):
    return nights.stored_form(nights.NightModel.model_validate(make_night(**overrides)))


# ------------------------------------------------------------------ validation

# Exactly what the app sends for this night (NightSyncTests.testANightIsSentExactlyAsTheServerIsTestedToAccept
# checks the app's encoder produces these bytes), so a change to either side breaks a test on the other.
APP_PAYLOAD_JSON = (
    '{"colors":["White","Red"],"currency":"USD","defaultBuyInMinor":2500,"denominationsMinor":{"Red":100,"White":25},'
    '"id":"11111111-2222-3333-4444-555555555555","location":"Pat\'s garage","pauses":[],'
    '"players":[{"buyIns":[{"amountMinor":2500,"at":"2026-08-06T19:00:00.000Z","id":"CCCCCCCC-2222-3333-4444-555555555555"}],'
    '"id":"AAAAAAAA-2222-3333-4444-555555555555","name":"Sam"}],"schemaVersion":1,"startedAt":"2026-08-06T19:00:00.000Z",'
    '"tzIdentifier":"America/Los_Angeles","updatedAt":"2026-08-06T19:00:00.000Z"}'
)


def test_what_the_app_sends_is_accepted_and_stored_unchanged():
    model = nights.NightModel.model_validate_json(APP_PAYLOAD_JSON)
    assert json.dumps(nights.stored_form(model), sort_keys=True, separators=(",", ":")) == APP_PAYLOAD_JSON


def test_a_normal_night_is_accepted_and_stored_in_its_canonical_form():
    document = stored()
    assert document["id"] == NIGHT_ID
    assert document["players"][0]["buyIns"][0]["amountMinor"] == 2500
    assert "endedAt" not in document and "resolution" not in document  # absent optionals stay absent
    # Canonical form is a fixed point: validating it again changes nothing.
    assert nights.stored_form(nights.NightModel.model_validate(document)) == document


def test_ids_are_stored_in_the_same_letter_case_the_app_writes():
    document = stored(id=NIGHT_ID.lower())
    assert document["id"] == NIGHT_ID  # Swift's UUID.uuidString is upper case


def test_instants_are_stored_as_utc_milliseconds():
    document = stored(startedAt="2026-08-06T12:00:00.1239-07:00", updatedAt="2026-08-06T19:00:01Z")
    assert document["startedAt"] == "2026-08-06T19:00:00.123Z"
    assert document["updatedAt"] == "2026-08-06T19:00:01.000Z"


def player_id_variant(index):
    player = copy.deepcopy(make_night()["players"][0])
    player["id"] = f"{index:08X}-2222-3333-4444-555555555555"
    return player


@pytest.mark.parametrize("change, fragment", [
    ({"defaultBuyInMinor": -1}, "defaultBuyInMinor"),
    ({"currency": "usd"}, "currency"),
    ({"schemaVersion": 2}, "schemaVersion"),
    ({"schemaVersion": 0}, "schemaVersion"),
    ({"id": "not-a-uuid"}, "id"),
    ({"startedAt": "2026-08-06T19:00:00"}, "startedAt"),          # no time zone
    ({"startedAt": "1999-12-31T23:59:59Z"}, "startedAt"),
    ({"updatedAt": None}, "updatedAt"),
    ({"notes": "x" * 2001}, "notes"),
    ({"location": "x" * 81}, "location"),
    ({"colors": [f"Color{i}" for i in range(13)]}, "colors"),
    ({"colors": ["__reserved__"]}, "colors"),
    ({"denominationsMinor": {"White": 0}}, "denominationsMinor"),
    ({"denominationsMinor": {"White": nights.MAX_MINOR + 1}}, "denominationsMinor"),
    ({"startingCounts": {"White": -1}}, "startingCounts"),
    ({"somethingNew": True}, "somethingNew"),
    ({"players": [player_id_variant(i) for i in range(nights.MAX_PLAYERS + 1)]}, "players"),
])
def test_a_malformed_night_is_refused_and_the_problem_is_named(change, fragment):
    with pytest.raises(ValidationError) as caught:
        nights.NightModel.model_validate(make_night(**change))
    assert fragment in nights.describe(caught.value)


def player_with(**overrides):
    player = copy.deepcopy(make_night()["players"][0])
    player.update(overrides)
    return player


@pytest.mark.parametrize("player, fragment", [
    (player_with(name=""), "name"),
    (player_with(name="   "), "name"),
    (player_with(name="x" * 41), "name"),
    (player_with(buyIns=[]), "buyIns"),
    (player_with(buyIns=[{"id": "EEEEEEEE-2222-3333-4444-555555555555", "amountMinor": 0, "at": "2026-08-06T19:00:00Z"}]), "amountMinor"),
    (player_with(buyIns=[{"id": "EEEEEEEE-2222-3333-4444-555555555555", "amountMinor": -5, "at": "2026-08-06T19:00:00Z"}]), "amountMinor"),
    (player_with(cashOutMinor=-1), "cashOutMinor"),
    (player_with(cashOutMinor=nights.MAX_CASH_OUT_MINOR + 1), "cashOutMinor"),
    (player_with(nickname="Sammy"), "nickname"),
])
def test_a_malformed_player_is_refused(player, fragment):
    with pytest.raises(ValidationError) as caught:
        nights.NightModel.model_validate(make_night(players=[player]))
    assert fragment in nights.describe(caught.value)


def test_two_players_cannot_share_an_id():
    clone = copy.deepcopy(make_night()["players"][0])
    with pytest.raises(ValidationError):
        nights.NightModel.model_validate(make_night(players=[clone, clone]))


def test_the_description_of_a_problem_never_repeats_what_was_typed():
    secret = "Margaret Hamilton " * 3
    with pytest.raises(ValidationError) as caught:
        nights.NightModel.model_validate(make_night(players=[player_with(name=secret)]))
    message = nights.describe(caught.value)
    assert "Margaret" not in message
    assert "players.0.name" in message


def test_which_player_is_the_phones_owner_is_kept_and_the_marker_forgets_it():
    document = stored(myPlayerID=SAM.lower())
    assert document["myPlayerID"] == SAM
    deleted = stored(myPlayerID=SAM, deletedAt="2026-08-06T21:00:00.000Z", updatedAt="2026-08-06T21:00:00.000Z")
    assert "myPlayerID" not in deleted


def test_a_bank_resolution_is_part_of_the_night():
    resolution = {"kind": "assign", "playerID": SAM.lower(), "deltaMinor": -200}
    document = stored(resolution=resolution)
    assert document["resolution"] == {"kind": "assign", "playerID": SAM, "deltaMinor": -200}
    with pytest.raises(ValidationError):
        nights.NightModel.model_validate(make_night(resolution={"kind": "round-it-off", "deltaMinor": 1}))


# ------------------------------------------------------------------ tombstones

# The same literal appears in the app's tests (NightSyncTests.testADeletedNightIsReducedToWhatTheServerKeeps),
# which is what keeps the two sides' idea of "nothing but the marker" the same.
TOMBSTONE_JSON = (
    '{"colors":[],"currency":"USD","defaultBuyInMinor":0,"deletedAt":"2026-08-06T21:00:00.000Z",'
    '"denominationsMinor":{},"id":"11111111-2222-3333-4444-555555555555","pauses":[],"players":[],'
    '"schemaVersion":1,"startedAt":"2026-08-06T19:00:00.000Z","tzIdentifier":"America/Los_Angeles",'
    '"updatedAt":"2026-08-06T21:00:00.000Z"}'
)


def test_a_deleted_night_keeps_a_marker_and_nothing_about_who_played():
    document = stored(deletedAt="2026-08-06T21:00:00.000Z", updatedAt="2026-08-06T21:00:00.000Z")
    assert json.dumps(document, sort_keys=True, separators=(",", ":")) == TOMBSTONE_JSON
    text = json.dumps(document)
    for private in ("Sam", "Alex", "garage", "Rain"):
        assert private not in text


def test_a_live_night_keeps_everything():
    text = json.dumps(stored())
    for kept in ("Sam", "Alex", "garage", "Rain"):
        assert kept in text


def test_the_servers_bookkeeping_is_not_sent_back():
    assert nights.public_form({**stored(), "serverUpdatedAt": "2026-08-06T19:00:00.000001+00:00"}) == stored()


# ------------------------------------------------------------------- the rule

def test_the_first_version_is_always_kept():
    assert nights.decide_put(None, stored()) == nights.PutDecision(write=True, applied=True)


def test_a_later_edit_replaces_the_earlier_one():
    later = stored(updatedAt="2026-08-06T19:00:00.001Z")
    assert nights.decide_put(stored(), later) == nights.PutDecision(write=True, applied=True)


def test_sending_the_same_version_again_changes_nothing_but_still_succeeds():
    held = {**stored(), "serverUpdatedAt": "2026-08-06T19:00:05.000000+00:00"}
    assert nights.decide_put(held, stored()) == nights.PutDecision(write=False, applied=True)


def test_an_earlier_edit_never_overwrites_a_later_one():
    held = stored(updatedAt="2026-08-06T20:00:00.000Z")
    assert nights.decide_put(held, stored()) == nights.PutDecision(write=False, applied=False)


def test_a_tie_with_different_content_keeps_what_the_server_has():
    held = stored(notes="from the phone")
    assert nights.decide_put(held, stored(notes="from the iPad")) == nights.PutDecision(write=False, applied=False)


def test_an_undo_beats_the_deletion_it_undoes_and_a_deletion_beats_the_edit_before_it():
    deleted = stored(deletedAt="2026-08-06T21:00:00.000Z", updatedAt="2026-08-06T21:00:00.000Z")
    undone = stored(updatedAt="2026-08-06T21:00:30.000Z")
    assert nights.decide_put(deleted, undone).applied is True
    assert nights.decide_put(undone, deleted).applied is False
    assert nights.decide_put(stored(), deleted).applied is True


def test_two_devices_always_end_up_with_the_same_night():
    """Three edits of one night reach the server in any order, with plenty of equal
    stamps. The server ends up with the latest stamp (the first to arrive, on a
    tie), and no device is left holding a different version of it."""
    rng = random.Random(20261009)
    for trial in range(500):
        stamps = [f"2026-08-06T19:00:0{rng.randint(0, 3)}.000Z" for _ in range(3)]
        versions = [stored(updatedAt=stamp, notes=f"v{index}") for index, stamp in enumerate(stamps)]
        devices = list(versions)
        order = [0, 1, 2]
        rng.shuffle(order)

        server = None
        for index in order:
            decision = nights.decide_put(server, devices[index])
            if decision.write:
                server = devices[index]
            if not decision.applied:
                devices[index] = server          # the app adopts what the server answered

        newest = max(stamps)
        first_to_arrive = next(index for index in order if stamps[index] == newest)
        assert server == versions[first_to_arrive], trial
        for device in devices:
            # Either it is the server's version, or it is older and the next pull replaces it.
            assert device == server or device["updatedAt"] < server["updatedAt"], trial


def test_the_result_does_not_depend_on_arrival_order_when_stamps_differ():
    rng = random.Random(7)
    versions = [stored(updatedAt=f"2026-08-06T19:00:{second:02d}.000Z", notes=f"v{second}") for second in range(6)]
    for _ in range(200):
        server = None
        for version in rng.sample(versions, len(versions)):
            if nights.decide_put(server, version).write:
                server = version
        assert server["notes"] == "v5"


# --------------------------------------------------------------------- cursors

@pytest.mark.parametrize("raw, expected", [
    ("2026-08-06T19:00:00.123000+00:00", "2026-08-06T19:00:00.123000+00:00"),
    ("2026-08-06T19:00:00.123Z", "2026-08-06T19:00:00.123000+00:00"),
    ("2026-08-06T12:00:00-07:00", "2026-08-06T19:00:00.000000+00:00"),
])
def test_a_cursor_is_normalised_to_the_form_the_server_stores(raw, expected):
    assert nights.normalize_cursor(raw) == expected


@pytest.mark.parametrize("raw", ["", "yesterday", "2026-08-06T19:00:00", "2026-13-40T00:00:00Z"])
def test_a_bad_cursor_is_refused(raw):
    with pytest.raises(ValueError):
        nights.normalize_cursor(raw)


# ------------------------------------------------------------- legacy sessions

def legacy_record(**overrides):
    record = {
        "status": "complete",
        "buyIn": 25.0,
        "buyInCents": 2500,
        "denominations": {"Red": 0.5, "White": 0.25, "Black": 5.0},
        "finalCounts": {"White": 40, "Red": 30, "Black": 4},
        "elapsedSeconds": 5400,
        "endingValue": 45.0,
        "endingValueCents": 4500,
        "profitLoss": 20.0,
        "profitLossCents": 2000,
        "startedAt": "2026-08-06T19:00:00.000000+00:00",
        "tzIdentifier": "America/Los_Angeles",
        "createdAt": "2026-08-06T20:35:00.000000+00:00",
        "updatedAt": "2026-08-06T20:35:00.000000+00:00",
    }
    record.update(overrides)
    return record


def test_an_old_session_becomes_a_one_player_night_with_the_same_money():
    night = nights.legacy_night("u1", "s1", legacy_record())
    model = nights.NightModel.model_validate(night)

    assert night["source"] == "legacy-session"
    assert [p.name for p in model.players] == ["Me"]
    assert night["myPlayerID"] == night["players"][0]["id"], "the one player is the person who used the app"
    assert model.players[0].buyIns[0].amountMinor == 2500
    assert model.players[0].cashOutMinor == 4500
    assert night["startedAt"] == "2026-08-06T19:00:00.000Z"
    assert night["endedAt"] == "2026-08-06T20:30:00.000Z"           # start + the 5,400 s that were played
    assert night["settledAt"] == "2026-08-06T20:35:00.000Z"
    assert night["colors"] == ["White", "Red", "Black"]               # lowest value first
    assert night["denominationsMinor"] == {"Red": 50, "White": 25, "Black": 500}
    assert night["tzIdentifier"] == "America/Los_Angeles"


def test_importing_the_same_session_twice_gives_the_same_night_and_other_accounts_get_their_own():
    first = nights.legacy_night("u1", "s1", legacy_record())
    assert nights.legacy_night("u1", "s1", legacy_record()) == first
    assert nights.legacy_night("u2", "s1", legacy_record())["id"] != first["id"]
    assert nights.legacy_night("u1", "s2", legacy_record())["id"] != first["id"]


def test_a_session_without_a_start_time_is_dated_from_when_it_was_saved():
    record = legacy_record()
    del record["startedAt"]
    night = nights.legacy_night("u1", "s1", record)
    assert night["endedAt"] == "2026-08-06T20:35:00.000Z"
    assert night["startedAt"] == "2026-08-06T19:05:00.000Z"


def test_a_session_saved_in_dollars_only_still_imports():
    record = legacy_record()
    for key in ("buyInCents", "endingValueCents"):
        del record[key]
    night = nights.legacy_night("u1", "s1", record)
    assert night["players"][0]["buyIns"][0]["amountMinor"] == 2500
    assert night["players"][0]["cashOutMinor"] == 4500


@pytest.mark.parametrize("record", [
    legacy_record(status="pending"),                  # only a photo was uploaded
    legacy_record(buyInCents=0, buyIn=0),             # nothing was put in
    legacy_record(createdAt="yesterday"),
    {"status": "complete"},
    {},
])
def test_a_session_that_cannot_be_a_night_is_skipped(record):
    assert nights.legacy_night("u1", "s1", record) is None
