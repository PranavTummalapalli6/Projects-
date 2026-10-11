//
//  NightStoreTests.swift
//  PokerChipAppTests
//
//  Keeping nights safe on the device: files that survive a restart, a bad file
//  that is set aside rather than lost, older and newer formats, and the store's
//  rules for stamping, queueing for the server, merging and deleting.
//

import XCTest
@testable import PokerChipApp

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func makeNight(id: UUID = UUID(), at start: Date = t0, names: [String] = ["Sam", "Alex"]) -> GameNight {
    GameNight.start(
        id: id, now: start, buyInMinor: 2_500, playerNames: names,
        colors: ["White", "Red"], denominationsMinor: ["White": 25, "Red": 100]
    )
}

private final class TestClock {
    var now = t0
    func tick(_ seconds: TimeInterval = 1) { now = now.addingTimeInterval(seconds) }
}

// MARK: - Files

final class FileNightRepositoryTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("nights-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func nightFile(_ id: UUID) -> URL {
        directory.appendingPathComponent("nights/\(id.uuidString).json")
    }

    private func writeRaw(_ text: String, id: UUID) throws {
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("nights"), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: nightFile(id))
    }

    func testNightsComeBackExactlyAsSaved() throws {
        let repository = FileNightRepository(directory: directory)
        let first = makeNight(), second = makeNight(at: t0.addingTimeInterval(3_600), names: ["Jo", "Pat", "Kim"])
        try repository.save(first)
        try repository.save(second)

        let loaded = try repository.loadAll()
        XCTAssertEqual(Set(loaded.nights.map(\.id)), [first.id, second.id])
        XCTAssertEqual(loaded.nights.first { $0.id == second.id }, second)
        XCTAssertEqual(loaded.quarantinedCount, 0)
    }

    func testSavingAgainReplacesTheNightInsteadOfAddingAFile() throws {
        let repository = FileNightRepository(directory: directory)
        var night = makeNight()
        try repository.save(night)
        night.rebuy(night.players[0].id)
        try repository.save(night)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("nights").path)
        XCTAssertEqual(files, ["\(night.id.uuidString).json"], "no leftover temporary files")
        XCTAssertEqual(try repository.loadAll().nights.first?.totalInMinor, 7_500)
    }

    func testAFirstLaunchHasNothingToLoad() throws {
        let loaded = try FileNightRepository(directory: directory).loadAll()
        XCTAssertEqual(loaded, NightLoadResult())
        XCTAssertEqual(FileNightRepository(directory: directory).loadSyncState(), NightSyncState())
    }

    func testAFileThatCannotBeReadIsSetAsideNotDeleted() throws {
        let repository = FileNightRepository(directory: directory)
        let good = makeNight()
        try repository.save(good)
        let broken = UUID()
        try writeRaw("{ this is not json", id: broken)

        let loaded = try repository.loadAll()
        XCTAssertEqual(loaded.nights.map(\.id), [good.id], "the readable night is unaffected")
        XCTAssertEqual(loaded.quarantinedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: nightFile(broken).path))
        let setAside = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("quarantine").path)
        XCTAssertEqual(setAside.count, 1, "the bytes are kept for recovery")
        XCTAssertEqual(try repository.loadAll().quarantinedCount, 0, "and it isn't retried every launch")
    }

    func testANightMissingItsPlayersIsUnreadable() throws {
        let id = UUID()
        try writeRaw(#"{"id": "\#(id.uuidString)", "startedAt": "2026-08-06T19:00:00Z"}"#, id: id)
        XCTAssertEqual(try FileNightRepository(directory: directory).loadAll().quarantinedCount, 1)
    }

    func testANightFromANewerVersionIsLeftAloneAndNotShown() throws {
        let repository = FileNightRepository(directory: directory)
        let id = UUID()
        let text = #"{"schemaVersion": 99, "id": "\#(id.uuidString)", "someFutureField": true}"#
        try writeRaw(text, id: id)

        let loaded = try repository.loadAll()
        XCTAssertEqual(loaded.nights, [])
        XCTAssertEqual(loaded.newerVersionCount, 1)
        XCTAssertEqual(loaded.quarantinedCount, 0)
        XCTAssertEqual(try String(contentsOf: nightFile(id), encoding: .utf8), text, "untouched on disk")
    }

    // MARK: Migration

    /// A made-up first draft: one `buyInMinor` per player, no list of buy-ins.
    private let draftJSON = """
    {"schemaVersion": 0, "id": "11111111-2222-3333-4444-555555555555",
     "startedAt": "2026-08-06T19:00:00.000Z", "updatedAt": "2026-08-06T19:00:00.000Z", "defaultBuyInMinor": 2500,
     "players": [{"id": "AAAAAAAA-2222-3333-4444-555555555555", "name": "Sam", "buyInMinor": 2500}]}
    """

    private var draftMigrator: NightMigrator {
        NightMigrator(steps: [0: { object in
            var players = object["players"] as? [[String: Any]] ?? []
            for index in players.indices {
                let amount = players[index].removeValue(forKey: "buyInMinor") as? Int ?? 0
                let event: [String: Any] = ["id": UUID().uuidString, "amountMinor": amount, "at": object["startedAt"] ?? ""]
                players[index]["buyIns"] = [event]
            }
            object["players"] = players
        }])
    }

    func testAnOlderNightIsUpgradedAndRewrittenAtTheCurrentVersion() throws {
        let id = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        try writeRaw(draftJSON, id: id)
        let repository = FileNightRepository(directory: directory, migrator: draftMigrator)

        let loaded = try repository.loadAll()
        let night = try XCTUnwrap(loaded.nights.first)
        XCTAssertEqual(night.schemaVersion, GameNight.currentSchemaVersion)
        XCTAssertEqual(night.players.first?.totalInMinor, 2_500)
        XCTAssertEqual(night.players.first?.name, "Sam")

        let onDisk = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: nightFile(id))) as? [String: Any])
        XCTAssertEqual(onDisk["schemaVersion"] as? Int, GameNight.currentSchemaVersion, "the upgrade happens once")
    }

    func testAnOldNightWithNoUpgradePathIsSetAsideNotGuessedAt() throws {
        let id = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        try writeRaw(draftJSON, id: id)
        let loaded = try FileNightRepository(directory: directory).loadAll()   // the standard migrator knows no step 0
        XCTAssertEqual(loaded.nights, [])
        XCTAssertEqual(loaded.quarantinedCount, 1)
    }

    // MARK: Sync state

    func testTheSyncStateRoundTripsAndStartsEmpty() throws {
        let repository = FileNightRepository(directory: directory)
        let state = NightSyncState(ownerUID: "u1", cursor: "2026-08-06T19:00:00.000000+00:00", dirty: ["B", "A"], legacyImportedFor: "u1")
        try repository.saveSyncState(state)
        XCTAssertEqual(repository.loadSyncState(), state)
    }

    func testRemovingEverythingLeavesNothingBehind() throws {
        let repository = FileNightRepository(directory: directory)
        try repository.save(makeNight())
        try repository.saveSyncState(NightSyncState(ownerUID: "u1"))
        try repository.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(try repository.loadAll(), NightLoadResult())
        XCTAssertEqual(repository.loadSyncState(), NightSyncState())
        XCTAssertNoThrow(try repository.removeAll(), "removing twice is harmless")
    }
}

// MARK: - The store

@MainActor
final class NightStoreTests: XCTestCase {
    private let clock = TestClock()
    private let repository = MemoryNightRepository()
    private var store: NightStore!

    override func setUp() async throws {
        try await super.setUp()
        let clock = self.clock
        store = NightStore(repository: repository, clock: { clock.now })
        await store.load()
    }

    private func stamp(_ id: UUID) throws -> Date {
        try XCTUnwrap(store.night(id)).updatedAt
    }

    func testItIsReadyOnceLoadedAndEmptyToBeginWith() {
        XCTAssertEqual(store.phase, .ready)
        XCTAssertEqual(store.nights, [])
        XCTAssertNil(store.openNight)
        XCTAssertEqual(store.problems, [])
    }

    func testStartingANightSavesItAndQueuesItForTheServer() {
        let night = store.start(makeNight())
        XCTAssertEqual(repository.nights[night.id]?.id, night.id, "saved straight away")
        XCTAssertEqual(store.pending.map(\.id), [night.id])
        XCTAssertEqual(repository.syncState.dirty, [night.id.uuidString])
        XCTAssertEqual(store.nights.map(\.id), [night.id])
        XCTAssertEqual(store.openNight?.id, night.id)
    }

    func testEveryChangeIsStampedLaterThanTheLastEvenIfTheClockGoesBackwards() throws {
        let night = store.start(makeNight())
        var previous = try XCTUnwrap(store.night(night.id)).updatedAt

        store.mutate(night.id) { $0.rebuy($0.players[0].id) }
        var current = try XCTUnwrap(store.night(night.id)).updatedAt
        XCTAssertGreaterThan(current, previous, "same instant on the clock still moves forward")

        previous = current
        clock.now = t0.addingTimeInterval(-3_600)            // the phone's clock is set back an hour
        store.mutate(night.id) { $0.rebuy($0.players[1].id) }
        current = try XCTUnwrap(store.night(night.id)).updatedAt
        XCTAssertGreaterThan(current, previous, "never earlier than the previous edit")
    }

    func testStampsAreWholeMillisecondsSoTheyComeBackEqual() throws {
        clock.now = Date(timeIntervalSince1970: 1_800_000_000.123_456_7)
        let night = store.start(makeNight())
        let stored = try XCTUnwrap(repository.nights[night.id])
        let data = try NightCoding.makeEncoder().encode(stored)
        XCTAssertEqual(try NightCoding.makeDecoder().decode(GameNight.self, from: data).updatedAt, stored.updatedAt)
    }

    func testAChangeThatChangesNothingIsNeitherSavedNorQueued() throws {
        let night = store.start(makeNight())
        store.markSynced(night.id, version: try stamp(night.id))
        XCTAssertEqual(store.pending, [])

        clock.tick()
        XCTAssertFalse(store.mutate(night.id) { $0.renamePlayer($0.players[0].id, to: "Sam") })
        XCTAssertEqual(store.pending, [])
        XCTAssertFalse(store.mutate(UUID()) { $0.endPlay() }, "an unknown night is ignored")
    }

    func testNightsAreListedNewestFirst() {
        let older = store.start(makeNight(at: t0))
        let newer = store.start(makeNight(at: t0.addingTimeInterval(86_400)))
        XCTAssertEqual(store.nights.map(\.id), [newer.id, older.id])
    }

    func testTheOpenNightIsTheNewestOneNotYetSettled() {
        let older = store.start(makeNight(at: t0))
        let newer = store.start(makeNight(at: t0.addingTimeInterval(86_400)))
        XCTAssertEqual(store.openNight?.id, newer.id)

        store.mutate(newer.id) { night in
            for player in night.players { night.cashOut(player.id, amountMinor: night.defaultBuyInMinor) }
            night.settle()
        }
        XCTAssertEqual(store.openNight?.id, older.id)
    }

    func testDeletingHidesANightAndRestoringBringsItBackWithItsDetails() throws {
        let night = store.start(makeNight(names: ["Sam", "Alex", "Jo"]))
        store.delete(night.id)
        XCTAssertNil(store.night(night.id))
        XCTAssertEqual(store.nights, [])
        XCTAssertNil(store.openNight)
        XCTAssertTrue(store.pending.contains { $0.id == night.id }, "the deletion is queued too")

        store.restore(night.id)
        let restored = try XCTUnwrap(store.night(night.id))
        XCTAssertEqual(restored.players.map(\.name), ["Sam", "Alex", "Jo"])
        XCTAssertNil(restored.deletedAt)
    }

    func testOnceUndoIsOverADeletedNightKeepsOnlyItsMarker() throws {
        let night = store.start(makeNight(names: ["Sam", "Alex"]))
        store.delete(night.id)
        let deleted = try XCTUnwrap(repository.nights[night.id])

        clock.tick(30)
        store.stripDeleted(olderThan: 60)
        XCTAssertEqual(repository.nights[night.id]?.players.count, 2, "still within the undo window")

        clock.tick(60)
        store.stripDeleted(olderThan: 60)
        let stripped = try XCTUnwrap(repository.nights[night.id])
        XCTAssertEqual(stripped, deleted.tombstone)
        XCTAssertEqual(stripped.players, [])
        XCTAssertNil(stripped.location)
        XCTAssertEqual(stripped.updatedAt, deleted.updatedAt, "same version, fewer details")
        XCTAssertTrue(stripped.isDeleted)
    }

    func testAFailedSaveIsReportedAndRetriedWhenThereIsRoom() {
        repository.failsToSave = true
        let night = store.start(makeNight())
        XCTAssertEqual(store.problems, [.couldNotSave])
        XCTAssertEqual(store.nights.map(\.id), [night.id], "the night is still there in memory")
        XCTAssertNil(repository.nights[night.id])

        repository.failsToSave = false
        store.retrySaving()
        XCTAssertEqual(store.problems, [])
        XCTAssertNotNil(repository.nights[night.id])
    }

    // MARK: Merging with the server

    func testANightFromTheServerIsAddedWithoutBeingQueued() {
        let remote = makeNight()
        XCTAssertEqual(store.merge(remote), .inserted)
        XCTAssertEqual(store.nights.map(\.id), [remote.id])
        XCTAssertEqual(store.pending, [])
    }

    func testTheLaterEditWins() throws {
        let local = store.start(makeNight(names: ["Sam", "Alex"]))
        var newer = local
        newer.renamePlayer(newer.players[0].id, to: "Samuel")
        newer.updatedAt = local.updatedAt.addingTimeInterval(5)

        XCTAssertEqual(store.merge(newer), .replaced)
        XCTAssertEqual(store.night(local.id)?.players[0].name, "Samuel")
        XCTAssertEqual(store.pending, [], "the server's version is now ours; nothing left to send")

        var older = newer
        older.renamePlayer(older.players[0].id, to: "Old")
        older.updatedAt = local.updatedAt.addingTimeInterval(-5)
        XCTAssertEqual(store.merge(older), .keptLocal)
        XCTAssertEqual(store.night(local.id)?.players[0].name, "Samuel")
    }

    func testALocalEditNewerThanTheServersStaysQueued() {
        let local = store.start(makeNight())
        var stale = local
        stale.updatedAt = local.updatedAt.addingTimeInterval(-10)
        stale.renamePlayer(stale.players[0].id, to: "Stale")

        XCTAssertEqual(store.merge(stale), .keptLocal)
        XCTAssertEqual(store.pending.map(\.id), [local.id])
        XCTAssertNotEqual(store.night(local.id)?.players[0].name, "Stale")
    }

    func testTheSameVersionAgainChangesNothing() {
        let local = store.start(makeNight())
        store.markSynced(local.id, version: local.updatedAt)
        XCTAssertEqual(store.merge(local), .identical)
        XCTAssertEqual(store.pending, [])
    }

    func testAdoptingTakesTheServersVersionEvenAtTheSameStamp() throws {
        let local = store.start(makeNight(names: ["Sam", "Alex"]))
        var theirs = local
        theirs.notes = "from the other phone"                 // same stamp, different content
        XCTAssertEqual(store.merge(theirs), .keptLocal, "a pull alone doesn't pick a side on a tie")

        store.adopt(theirs)                                    // …the server's answer to a push does
        XCTAssertEqual(store.night(local.id)?.notes, "from the other phone")
        XCTAssertEqual(store.pending, [])
        XCTAssertEqual(repository.nights[local.id]?.notes, "from the other phone")
    }

    func testAnEditMadeWhileTheServerWasBeingToldIsStillQueued() throws {
        let night = store.start(makeNight())
        let sent = try XCTUnwrap(store.night(night.id)).updatedAt           // the version that went out
        clock.tick()
        store.mutate(night.id) { $0.rebuy($0.players[0].id) }                // edited while the request was in flight

        store.markSynced(night.id, version: sent)
        XCTAssertEqual(store.pending.map(\.id), [night.id], "the newer edit hasn't reached the server")

        store.markSynced(night.id, version: try XCTUnwrap(store.night(night.id)).updatedAt)
        XCTAssertEqual(store.pending, [])
    }

    func testPendingChangesGoOutOldestFirst() {
        let first = store.start(makeNight(at: t0))
        clock.tick(10)
        let second = store.start(makeNight(at: t0.addingTimeInterval(-1_000)))
        clock.tick(10)
        store.mutate(first.id) { $0.rebuy($0.players[0].id) }
        XCTAssertEqual(store.pending.map(\.id), [second.id, first.id])
    }

    // MARK: Accounts

    func testSwitchingAccountsSendsEverythingOnThisPhoneToTheNewAccount() throws {
        let night = store.start(makeNight())
        store.attach(to: "alice")
        store.markSynced(night.id, version: try stamp(night.id))
        store.setCursor("cursor-1")
        store.markLegacyImported(for: "alice")
        XCTAssertEqual(store.pending, [])

        store.attach(to: "alice")                              // same account: nothing changes
        XCTAssertEqual(store.cursor, "cursor-1")
        XCTAssertEqual(store.pending, [])

        store.attach(to: "bob")
        XCTAssertEqual(store.ownerUID, "bob")
        XCTAssertNil(store.cursor, "bob's history is pulled from the start")
        XCTAssertNil(store.legacyImportedFor)
        XCTAssertEqual(store.pending.map(\.id), [night.id])
    }

    func testResettingLeavesNothingOnThePhone() {
        store.start(makeNight())
        store.attach(to: "alice")
        store.reset()
        XCTAssertEqual(store.nights, [])
        XCTAssertEqual(store.pending, [])
        XCTAssertNil(store.ownerUID)
        XCTAssertEqual(repository.nights.count, 0)
    }

    // MARK: Across launches

    func testNightsTheQueueAndTheCursorSurviveRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("relaunch-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let files = FileNightRepository(directory: directory)

        let clock = self.clock
        let first = NightStore(repository: files, clock: { clock.now })
        await first.load()
        let synced = first.start(makeNight(at: t0))
        let waiting = first.start(makeNight(at: t0.addingTimeInterval(60)))
        first.attach(to: "alice")
        first.markSynced(synced.id, version: try XCTUnwrap(first.night(synced.id)).updatedAt)
        first.setCursor("cursor-9")

        let second = NightStore(repository: FileNightRepository(directory: directory), clock: { clock.now })
        await second.load()
        XCTAssertEqual(second.nights.map(\.id), [waiting.id, synced.id])
        XCTAssertEqual(second.pending.map(\.id), [waiting.id])
        XCTAssertEqual(second.cursor, "cursor-9")
        XCTAssertEqual(second.ownerUID, "alice")
        XCTAssertEqual(second.night(waiting.id), first.night(waiting.id))
    }

    func testProblemsFoundWhileLoadingAreReported() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("problems-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let nights = directory.appendingPathComponent("nights")
        try FileManager.default.createDirectory(at: nights, withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: nights.appendingPathComponent("\(UUID().uuidString).json"))
        try Data(#"{"schemaVersion": 7, "id": "x"}"#.utf8).write(to: nights.appendingPathComponent("\(UUID().uuidString).json"))

        let store = NightStore(repository: FileNightRepository(directory: directory))
        await store.load()
        XCTAssertEqual(store.problems, [.unreadable(1), .newerVersion(1)])
        XCTAssertFalse(store.problems.map(\.message).contains(""))
    }
}

// MARK: - Undoing a deletion

@MainActor
final class UndoDeleteTests: XCTestCase {
    private func makeStore() async -> NightStore {
        let store = NightStore(repository: MemoryNightRepository(), clock: { t0 })
        await store.load()
        return store
    }

    func testADeletedNightIsRememberedForUndoUntilItIsRestored() async {
        let store = await makeStore()
        let night = store.start(makeNight())
        XCTAssertNil(store.lastDeletedID)

        store.delete(night.id)
        XCTAssertEqual(store.lastDeletedID, night.id)
        XCTAssertNil(store.night(night.id))

        store.restore(night.id)
        XCTAssertNil(store.lastDeletedID)
        XCTAssertNotNil(store.night(night.id))
    }

    func testDeletingSomethingThatIsNotThereChangesNothing() async {
        let store = await makeStore()
        store.delete(UUID())
        XCTAssertNil(store.lastDeletedID)
    }

    func testResettingForgetsWhatCouldHaveBeenUndone() async {
        let store = await makeStore()
        let night = store.start(makeNight())
        store.delete(night.id)
        store.reset()
        XCTAssertNil(store.lastDeletedID)
    }

    func testTheUndoWindowIsShortButLongEnoughToReach() {
        XCTAssertGreaterThanOrEqual(NightStore.undoWindow, 5)
        XCTAssertLessThanOrEqual(NightStore.undoWindow, 15)
    }
}
