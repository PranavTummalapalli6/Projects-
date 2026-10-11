//
//  NightSyncTests.swift
//  PokerChipAppTests
//
//  Two phones and a server that follows the real server's rules (app/nights.py):
//  the later edit wins, repeating a version changes nothing, a tie keeps the
//  first writer, a deleted night shrinks to a marker, and changes are listed
//  oldest first. Around that: the ways a sync can go wrong, and none of them
//  may lose a night.
//

import XCTest
@testable import PokerChipApp

private let t0 = Date(timeIntervalSince1970: 1_786_042_800)    // 2026-08-06T19:00:00Z

private func makeNight(id: UUID = UUID(), at start: Date = t0, names: [String] = ["Sam", "Alex"]) -> GameNight {
    GameNight.start(
        id: id, now: start, buyInMinor: 2_500, playerNames: names,
        colors: ["White", "Red"], denominationsMinor: ["White": 25, "Red": 100]
    )
}

// MARK: - A server with the real one's rules

final class FakeNightServer {
    struct Entry {
        var night: GameNight
        var stamp: String
    }

    private(set) var entries: [UUID: Entry] = [:]
    private(set) var requests: [String] = []
    private var tick = 0
    var legacyNightsToAdd: [GameNight] = []

    /// Behave as if there is no connection.
    var offline = false
    /// Answer matching requests with a fixed status and body instead.
    var overrides: [(matches: (String) -> Bool, status: Int, body: String)] = []
    /// Runs on the main actor while a request is in flight, to simulate the person tapping meanwhile.
    var duringRequest: (@MainActor (String) -> Void)?

    func requests(matching prefix: String) -> [String] { requests.filter { $0.hasPrefix(prefix) } }

    // The server's own clock: one second per change, written as the real server writes it.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private func stamp(_ tick: Int) -> String {
        Self.formatter.string(from: Date(timeIntervalSince1970: 1_786_060_000 + TimeInterval(tick))) + ".000000+00:00"
    }

    /// Same rules as `decide_put` in app/nights.py. Returns what the server holds afterwards and whether the offer was kept.
    @discardableResult
    func put(_ incoming: GameNight, atTick forcedTick: Int? = nil) -> (night: GameNight, stamp: String, applied: Bool) {
        let offered = incoming.deletedAt == nil ? incoming : incoming.tombstone
        var applied = true
        var write = true
        if let held = entries[offered.id]?.night {
            if offered.updatedAt > held.updatedAt {
                write = true
            } else if offered.updatedAt == held.updatedAt && offered == held {
                write = false
            } else {
                write = false
                applied = false
            }
        }
        if write {
            tick += 1
            entries[offered.id] = Entry(night: offered, stamp: stamp(forcedTick ?? tick))
        }
        let current = entries[offered.id] ?? Entry(night: offered, stamp: stamp(0))
        return (current.night, current.stamp, applied)
    }

    // MARK: Wire

    func client() -> ChipVisionAPIClient {
        ChipVisionAPIClient(
            transport: { [self] request in try await handle(request) },
            baseURL: { URL(string: "https://api.example.test") ?? URL(fileURLWithPath: "/") },
            tokenProvider: { _ in "token" },
            sleep: { _ in }
        )
    }

    private func json(_ night: GameNight) throws -> Any {
        try JSONSerialization.jsonObject(with: NightCoding.makeEncoder().encode(night))
    }

    private func reply(_ url: URL, _ status: Int, _ object: Any) throws -> (Data, URLResponse) {
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        return (data, response ?? URLResponse())
    }

    private func handle(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url ?? URL(fileURLWithPath: "/")
        let method = request.httpMethod ?? "GET"
        let label = "\(method) \(url.path)" + (url.query.map { "?\($0)" } ?? "")
        requests.append(label)
        if offline { throw URLError(.notConnectedToInternet) }
        if let hook = duringRequest { await hook(label) }

        if let override = overrides.first(where: { $0.matches(label) }) {
            let response = HTTPURLResponse(url: url, statusCode: override.status, httpVersion: nil, headerFields: nil)
            return (Data(override.body.utf8), response ?? URLResponse())
        }

        switch (method, url.path) {
        case ("PUT", let path) where path.hasPrefix("/v1/nights/"):
            let incoming = try NightCoding.makeDecoder().decode(GameNight.self, from: request.httpBody ?? Data())
            let result = put(incoming)
            return try reply(url, 200, ["night": try json(result.night), "applied": result.applied, "serverUpdatedAt": result.stamp])

        case ("GET", "/v1/nights"):
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let since = items.first { $0.name == "since" }?.value
            let limit = items.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 100
            let changed = entries.values
                .filter { since == nil || Self.comparable($0.stamp) > Self.comparable(since ?? "") }
                .sorted { $0.stamp < $1.stamp }
            let page = changed.prefix(limit)
            let cursor: Any
            if let last = page.last?.stamp { cursor = last } else if let since { cursor = since } else { cursor = NSNull() }
            return try reply(url, 200, ["nights": try page.map { try json($0.night) }, "cursor": cursor, "hasMore": changed.count > limit])

        case ("POST", "/v1/nights/import-legacy"):
            for night in legacyNightsToAdd where entries[night.id] == nil { put(night) }
            let added = legacyNightsToAdd.count
            legacyNightsToAdd = []
            return try reply(url, 200, ["imported": added])

        default:
            return try reply(url, 404, ["detail": "No such route"])
        }
    }

    /// Both "…05.000000+00:00" and "…04.995Z" as the same shape, so they compare as text.
    private static func comparable(_ iso: String) -> String {
        var text = iso
        if text.hasSuffix("Z") { text.removeLast() } else if text.hasSuffix("+00:00") { text.removeLast(6) }
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        return String(parts[0]) + "." + fraction.padding(toLength: 6, withPad: "0", startingAt: 0)
    }
}

// MARK: - A phone

@MainActor
private final class Phone {
    let clock: TestClock
    let repository: MemoryNightRepository
    let store: NightStore
    let sync: NightSync

    init(server: FakeNightServer, startingAt start: Date = t0) async {
        let clock = TestClock()
        clock.now = start
        let repository = MemoryNightRepository()
        let store = NightStore(repository: repository, clock: { clock.now })
        self.clock = clock
        self.repository = repository
        self.store = store
        self.sync = NightSync(store: store, client: { server.client() }, now: { clock.now }, sleep: { _ in })
        await store.load()
    }

    @discardableResult
    func startNight(at start: Date? = nil, names: [String] = ["Sam", "Alex"]) -> GameNight {
        store.start(makeNight(at: start ?? clock.now, names: names))
    }
}

private final class TestClock {
    var now = t0
    func tick(_ seconds: TimeInterval = 1) { now = now.addingTimeInterval(seconds) }
}

// MARK: - Tests

@MainActor
final class NightSyncTests: XCTestCase {
    private let server = FakeNightServer()

    // MARK: The ordinary case

    func testAFirstSyncWithNothingToSendJustChecksIn() async {
        let phone = await Phone(server: server)
        await phone.sync.sync(uid: "alice")

        XCTAssertEqual(phone.sync.status, .idle)
        XCTAssertNotNil(phone.sync.lastSyncedAt)
        XCTAssertEqual(server.requests.filter { $0.hasPrefix("PUT") }, [])
        XCTAssertEqual(phone.store.ownerUID, "alice")
    }

    func testANewNightGoesToTheServerAndLeavesTheQueue() async throws {
        let phone = await Phone(server: server)
        let night = phone.startNight()
        XCTAssertEqual(phone.store.pending.count, 1)

        await phone.sync.sync(uid: "alice")

        XCTAssertEqual(phone.sync.status, .idle)
        XCTAssertEqual(phone.store.pending, [])
        XCTAssertEqual(server.entries[night.id]?.night, phone.store.night(night.id))
        XCTAssertEqual(server.requests(matching: "PUT /v1/nights/\(night.id.uuidString)").count, 1)
    }

    func testNothingIsSentTwice() async {
        let phone = await Phone(server: server)
        phone.startNight()
        await phone.sync.sync(uid: "alice")
        await phone.sync.sync(uid: "alice")
        XCTAssertEqual(server.requests(matching: "PUT").count, 1)
    }

    func testEarlierSessionsAreImportedOncePerAccount() async {
        let phone = await Phone(server: server)
        server.legacyNightsToAdd = [makeNight(names: ["Me"])]
        await phone.sync.sync(uid: "alice")
        await phone.sync.sync(uid: "alice")

        XCTAssertEqual(server.requests(matching: "POST /v1/nights/import-legacy").count, 1)
        XCTAssertEqual(phone.store.nights.count, 1, "the imported night was pulled down")
        XCTAssertEqual(phone.store.pending, [])
    }

    // MARK: Two phones

    func testAnotherPhoneReceivesTheNightAndLaterEditsToIt() async throws {
        let first = await Phone(server: server)
        let second = await Phone(server: server)
        let night = first.startNight(names: ["Sam", "Alex", "Jo"])
        await first.sync.sync(uid: "alice")
        await second.sync.sync(uid: "alice")
        XCTAssertEqual(second.store.night(night.id)?.players.map(\.name), ["Sam", "Alex", "Jo"])

        second.clock.tick(60)
        second.store.mutate(night.id) { $0.rebuy($0.players[0].id) }
        await second.sync.sync(uid: "alice")
        await first.sync.sync(uid: "alice")

        XCTAssertEqual(first.store.night(night.id)?.players[0].rebuyCount, 1)
        XCTAssertEqual(first.store.night(night.id), second.store.night(night.id))
    }

    func testTheLaterOfTwoOfflineEditsWinsOnBothPhones() async throws {
        let first = await Phone(server: server)
        let second = await Phone(server: server)
        let night = first.startNight()
        await first.sync.sync(uid: "alice")
        await second.sync.sync(uid: "alice")

        first.clock.tick(100)
        first.store.mutate(night.id) { $0.notes = "typed on the first phone" }
        second.clock.tick(200)
        second.store.mutate(night.id) { $0.notes = "typed on the second phone, later" }

        await second.sync.sync(uid: "alice")        // the later edit reaches the server first…
        await first.sync.sync(uid: "alice")         // …and the earlier one is turned away and replaced
        await second.sync.sync(uid: "alice")

        XCTAssertEqual(first.store.night(night.id)?.notes, "typed on the second phone, later")
        XCTAssertEqual(second.store.night(night.id)?.notes, "typed on the second phone, later")
        XCTAssertEqual(server.entries[night.id]?.night.notes, "typed on the second phone, later")
        XCTAssertEqual(first.store.pending, [])
        XCTAssertEqual(second.store.pending, [])
    }

    func testTheOrderTheyReachTheServerInDoesNotChangeTheWinner() async throws {
        for firstGoesFirst in [true, false] {
            let server = FakeNightServer()
            let first = await Phone(server: server)
            let second = await Phone(server: server)
            let night = first.startNight()
            await first.sync.sync(uid: "alice")
            await second.sync.sync(uid: "alice")

            first.clock.tick(300)
            first.store.mutate(night.id) { $0.notes = "later" }
            second.clock.tick(100)
            second.store.mutate(night.id) { $0.notes = "earlier" }

            for phone in (firstGoesFirst ? [first, second] : [second, first]) { await phone.sync.sync(uid: "alice") }
            for phone in [first, second] { await phone.sync.sync(uid: "alice") }

            XCTAssertEqual(first.store.night(night.id)?.notes, "later", "firstGoesFirst: \(firstGoesFirst)")
            XCTAssertEqual(second.store.night(night.id)?.notes, "later", "firstGoesFirst: \(firstGoesFirst)")
        }
    }

    func testTwoEditsAtTheSameInstantEndUpIdenticalEverywhere() async throws {
        let first = await Phone(server: server)
        let second = await Phone(server: server)
        let night = first.startNight()
        await first.sync.sync(uid: "alice")
        await second.sync.sync(uid: "alice")

        first.clock.tick(100)
        second.clock.tick(100)                                   // the very same moment on both clocks
        first.store.mutate(night.id) { $0.notes = "from the first" }
        second.store.mutate(night.id) { $0.notes = "from the second" }

        await first.sync.sync(uid: "alice")
        await second.sync.sync(uid: "alice")
        await first.sync.sync(uid: "alice")

        XCTAssertEqual(first.store.night(night.id), second.store.night(night.id))
        XCTAssertEqual(first.store.night(night.id)?.notes, "from the first", "first writer keeps the tie")
        XCTAssertEqual(second.store.pending, [])
    }

    // MARK: Deleting

    func testADeletedNightDisappearsEverywhereAndTheServerKeepsOnlyAMarker() async throws {
        let first = await Phone(server: server)
        let second = await Phone(server: server)
        let night = first.startNight(names: ["Sam", "Alex"])
        await first.sync.sync(uid: "alice")
        await second.sync.sync(uid: "alice")
        XCTAssertNotNil(second.store.night(night.id))

        first.clock.tick(30)
        first.store.delete(night.id)
        await first.sync.sync(uid: "alice")
        await second.sync.sync(uid: "alice")

        XCTAssertNil(second.store.night(night.id))
        XCTAssertEqual(server.entries[night.id]?.night.players, [], "no names on the server")
        XCTAssertNotNil(server.entries[night.id]?.night.deletedAt)
        XCTAssertNil(first.store.night(night.id))
    }

    func testUndoAfterTheDeletionHasReachedTheServerBringsTheNightBackEverywhere() async throws {
        let first = await Phone(server: server)
        let second = await Phone(server: server)
        let night = first.startNight(names: ["Sam", "Alex"])
        await first.sync.sync(uid: "alice")
        await second.sync.sync(uid: "alice")

        first.clock.tick(30)
        first.store.delete(night.id)
        await first.sync.sync(uid: "alice")
        first.clock.tick(5)
        first.store.restore(night.id)                            // Undo: still has its details locally
        await first.sync.sync(uid: "alice")
        await second.sync.sync(uid: "alice")

        XCTAssertEqual(second.store.night(night.id)?.players.map(\.name), ["Sam", "Alex"])
        XCTAssertEqual(first.store.night(night.id), second.store.night(night.id))
    }

    // MARK: Pulling

    func testALongHistoryIsPulledInPages() async throws {
        let phone = await Phone(server: server)
        for index in 0..<250 {
            server.put(makeNight(at: t0.addingTimeInterval(TimeInterval(index))))
        }
        await phone.sync.sync(uid: "alice")

        XCTAssertEqual(phone.store.nights.count, 250)
        XCTAssertEqual(server.requests(matching: "GET").count, 3, "100 + 100 + 50")
        XCTAssertEqual(phone.store.cursor, server.entries.values.map(\.stamp).max())
    }

    func testASecondSyncStartsFromTheCursorNotFromTheBeginning() async throws {
        let phone = await Phone(server: server)
        for index in 0..<30 { server.put(makeNight(at: t0.addingTimeInterval(TimeInterval(index)))) }
        await phone.sync.sync(uid: "alice")
        let late = makeNight(at: t0.addingTimeInterval(1_000))
        server.put(late)
        await phone.sync.sync(uid: "alice")

        XCTAssertNotNil(phone.store.night(late.id))
        let lastPull = try XCTUnwrap(server.requests(matching: "GET").last)
        XCTAssertTrue(lastPull.contains("since="), lastPull)
    }

    func testAChangeTheServerStampedSlightlyOutOfOrderIsStillPickedUp() async throws {
        let phone = await Phone(server: server)
        for index in 0..<5 { server.put(makeNight(at: t0.addingTimeInterval(TimeInterval(index)))) }
        await phone.sync.sync(uid: "alice")                      // cursor is now at the 5th change

        // Another server instance with a slow clock stamped this one 3 seconds *before* our cursor.
        let skewed = makeNight(at: t0.addingTimeInterval(500))
        server.put(skewed, atTick: 2)
        await phone.sync.sync(uid: "alice")

        XCTAssertNotNil(phone.store.night(skewed.id), "the overlap re-reads a few seconds before the cursor")
    }

    func testReReadingNightsWeAlreadyHaveChangesNothing() async throws {
        let phone = await Phone(server: server)
        for index in 0..<10 { server.put(makeNight(at: t0.addingTimeInterval(TimeInterval(index)))) }
        await phone.sync.sync(uid: "alice")
        let before = phone.store.nights
        await phone.sync.sync(uid: "alice")
        XCTAssertEqual(phone.store.nights, before)
        XCTAssertEqual(phone.store.pending, [])
    }

    // MARK: Accounts

    func testSigningInAsSomeoneElseSendsThisPhonesNightsToThatAccount() async throws {
        let phone = await Phone(server: server)
        let night = phone.startNight()
        await phone.sync.sync(uid: "alice")

        let bobsServer = FakeNightServer()
        let asBob = NightSync(store: phone.store, client: { bobsServer.client() }, now: { phone.clock.now }, sleep: { _ in })
        await asBob.sync(uid: "bob")

        XCTAssertEqual(bobsServer.entries[night.id]?.night, phone.store.night(night.id))
        XCTAssertEqual(phone.store.ownerUID, "bob")
        XCTAssertEqual(phone.store.legacyImportedFor, "bob")
    }

    func testWithoutASignInNothingIsSentAndTheNightsStayPut() async {
        let phone = await Phone(server: server)
        phone.startNight()
        await phone.sync.sync(uid: nil)
        XCTAssertEqual(phone.sync.status, .needsSignIn)
        XCTAssertEqual(server.requests, [])
        XCTAssertEqual(phone.store.pending.count, 1)
    }

    // MARK: When things go wrong

    func testNoConnectionLeavesEverythingQueuedForNextTime() async {
        let phone = await Phone(server: server)
        let night = phone.startNight()
        server.offline = true
        await phone.sync.sync(uid: "alice")

        XCTAssertEqual(phone.sync.status, .offline)
        XCTAssertEqual(phone.store.pending.map(\.id), [night.id])
        XCTAssertNotNil(phone.store.night(night.id))

        server.offline = false
        await phone.sync.sync(uid: "alice")
        XCTAssertEqual(phone.sync.status, .idle)
        XCTAssertEqual(phone.store.pending, [])
        XCTAssertNotNil(server.entries[night.id])
    }

    func testASignInThatHasExpiredAsksToSignInAgainAndKeepsTheQueue() async {
        let phone = await Phone(server: server)
        phone.startNight()
        server.overrides = [({ $0.hasPrefix("PUT") }, 401, #"{"detail": "expired"}"#)]
        await phone.sync.sync(uid: "alice")
        XCTAssertEqual(phone.sync.status, .needsSignIn)
        XCTAssertEqual(phone.store.pending.count, 1)
    }

    func testAServerProblemIsReportedGentlyAndTheQueueIsKept() async {
        let phone = await Phone(server: server)
        phone.startNight()
        server.overrides = [({ $0.hasPrefix("PUT") }, 500, #"{"detail": "boom"}"#)]
        await phone.sync.sync(uid: "alice")

        guard case .failed(let message) = phone.sync.status else { return XCTFail("expected a failure, got \(phone.sync.status)") }
        XCTAssertTrue(message.contains("safe on this iPhone"))
        XCTAssertEqual(phone.store.pending.count, 1)
    }

    func testAServerThatDoesNotOfferSyncYetIsNotTreatedAsABreakage() async {
        let phone = await Phone(server: server)
        phone.startNight()
        server.overrides = [({ $0.contains("/v1/nights") }, 404, #"{"detail": "Not Found"}"#)]
        await phone.sync.sync(uid: "alice")
        XCTAssertEqual(phone.sync.status, .unavailable)
        XCTAssertEqual(phone.store.pending.count, 1, "still safe, still queued")
    }

    func testOneNightTheServerRefusesDoesNotStopTheOthers() async throws {
        let phone = await Phone(server: server)
        let refused = phone.startNight(names: ["Refused"])
        phone.clock.tick(10)
        let fine = phone.startNight(at: t0.addingTimeInterval(60), names: ["Fine"])
        server.overrides = [({ $0.hasPrefix("PUT /v1/nights/\(refused.id.uuidString)") }, 422, #"{"detail": "That night couldn't be saved"}"#)]

        await phone.sync.sync(uid: "alice")

        XCTAssertEqual(phone.sync.status, .idle)
        XCTAssertEqual(phone.sync.refusedCount, 1)
        XCTAssertNotNil(server.entries[fine.id])
        XCTAssertEqual(phone.store.pending.map(\.id), [refused.id], "kept on the phone, not lost")
        XCTAssertNotNil(phone.store.night(refused.id))
    }

    func testBeingToldToSlowDownIsNotTreatedAsABrokenNight() async {
        let phone = await Phone(server: server)
        phone.startNight()
        server.overrides = [({ $0.hasPrefix("PUT") }, 429, #"{"detail": "slow down"}"#)]
        await phone.sync.sync(uid: "alice")
        guard case .failed = phone.sync.status else { return XCTFail("expected a gentle failure, got \(phone.sync.status)") }
        XCTAssertEqual(phone.sync.refusedCount, 0)
        XCTAssertEqual(phone.store.pending.count, 1)
    }

    func testAnEditMadeWhileTheServerIsBeingToldGoesOutOnTheNextPass() async throws {
        let phone = await Phone(server: server)
        let night = phone.startNight()
        var edited = false
        server.duringRequest = { @MainActor [unowned phone] label in
            guard label.hasPrefix("PUT"), !edited else { return }
            edited = true
            phone.clock.tick(5)
            phone.store.mutate(night.id) { $0.rebuy($0.players[0].id) }      // a tap while the request is in flight
            Task { await phone.sync.sync(uid: "alice") }                     // the app notices and asks again
        }

        await phone.sync.sync(uid: "alice")

        XCTAssertEqual(phone.sync.status, .idle)
        XCTAssertEqual(phone.store.pending, [], "the second version went out too")
        XCTAssertEqual(server.entries[night.id]?.night.players[0].rebuyCount, 1)
        XCTAssertEqual(server.requests(matching: "PUT").count, 2)
    }

    func testSyncRequestsAreDebouncedIntoOne() async throws {
        let phone = await Phone(server: server)
        phone.startNight()
        phone.sync.schedule(uid: "alice")
        phone.sync.schedule(uid: "alice")
        phone.sync.schedule(uid: "alice")
        await phone.sync.waitForScheduledSync()

        XCTAssertEqual(server.requests(matching: "PUT").count, 1)
        XCTAssertEqual(phone.sync.status, .idle)
    }

    // MARK: The wire

    private let goldenNightJSON = """
    {"colors":["White","Red"],"currency":"USD","defaultBuyInMinor":2500,"denominationsMinor":{"Red":100,"White":25},\
    "id":"11111111-2222-3333-4444-555555555555","location":"Pat's garage","pauses":[],\
    "players":[{"buyIns":[{"amountMinor":2500,"at":"2026-08-06T19:00:00.000Z","id":"CCCCCCCC-2222-3333-4444-555555555555"}],\
    "id":"AAAAAAAA-2222-3333-4444-555555555555","name":"Sam"}],"schemaVersion":1,"startedAt":"2026-08-06T19:00:00.000Z",\
    "tzIdentifier":"America/Los_Angeles","updatedAt":"2026-08-06T19:00:00.000Z"}
    """

    /// The same text is validated by the server's tests (`APP_PAYLOAD_JSON` in test_nights.py).
    func testANightIsSentExactlyAsTheServerIsTestedToAccept() throws {
        let night = GameNight(
            id: try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555")),
            startedAt: t0, tzIdentifier: "America/Los_Angeles", defaultBuyInMinor: 2_500,
            location: "Pat's garage", colors: ["White", "Red"], denominationsMinor: ["White": 25, "Red": 100],
            players: [PlayerLedger(
                id: try XCTUnwrap(UUID(uuidString: "AAAAAAAA-2222-3333-4444-555555555555")), name: "Sam",
                buyIns: [BuyInEvent(id: try XCTUnwrap(UUID(uuidString: "CCCCCCCC-2222-3333-4444-555555555555")), amountMinor: 2_500, at: t0)],
                cashOutMinor: nil, cashedOutAt: nil
            )],
            updatedAt: t0
        )
        let sent = String(decoding: try NightCoding.makeEncoder().encode(night), as: UTF8.self)
        XCTAssertEqual(sent, goldenNightJSON)
        XCTAssertEqual(try NightCoding.makeDecoder().decode(GameNight.self, from: Data(goldenNightJSON.utf8)), night)
    }

    /// The same text appears in the server's tests (`TOMBSTONE_JSON` in test_nights.py).
    func testADeletedNightIsReducedToWhatTheServerKeeps() throws {
        var night = makeNight(id: try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555")), names: ["Sam", "Alex"])
        night.location = "Pat's garage"
        night.notes = "Rain delay"
        night.tzIdentifier = "America/Los_Angeles"
        night.markDeleted(at: t0.addingTimeInterval(7_200))
        night.updatedAt = t0.addingTimeInterval(7_200)

        let text = String(decoding: try NightCoding.makeEncoder().encode(night.tombstone), as: UTF8.self)
        XCTAssertEqual(text, """
        {"colors":[],"currency":"USD","defaultBuyInMinor":0,"deletedAt":"2026-08-06T21:00:00.000Z","denominationsMinor":{},\
        "id":"11111111-2222-3333-4444-555555555555","pauses":[],"players":[],"schemaVersion":1,\
        "startedAt":"2026-08-06T19:00:00.000Z","tzIdentifier":"America/Los_Angeles","updatedAt":"2026-08-06T21:00:00.000Z"}
        """)
    }

    func testTheServersCursorIsReadAndMovedBackExactly() throws {
        let cursor = "2026-08-07T00:00:15.250750+00:00"
        let date = try XCTUnwrap(NightCursor.date(from: cursor))
        XCTAssertEqual(date.timeIntervalSince1970, 1_786_060_815.250750, accuracy: 0.000_01)
        XCTAssertEqual(NightCursor.shifted(cursor, by: -10), "2026-08-07T00:00:05.250Z")
        XCTAssertEqual(NightCursor.shifted("2026-08-07T00:00:15+00:00", by: -10), "2026-08-07T00:00:05.000Z")
        XCTAssertNil(NightCursor.shifted("yesterday", by: -10))
    }
}
