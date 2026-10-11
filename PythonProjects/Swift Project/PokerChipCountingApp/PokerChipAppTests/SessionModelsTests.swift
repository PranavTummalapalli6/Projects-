//
//  SessionModelsTests.swift
//  PokerChipAppTests
//
//  The small things remembered between nights (the stores and the setup), and
//  decoding what the server sends back.
//

import XCTest
@testable import PokerChipApp

final class StoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func store() -> JSONDefaultsStore<GameSetup> {
        JSONDefaultsStore<GameSetup>(key: "setup", defaults: defaults)
    }

    func testAValueRoundTripsThroughTheStore() {
        let setup = GameSetup(buyIn: 25, players: 6, availableColors: ["White", "Red"])
        store().save(setup)
        XCTAssertEqual(store().load(), setup)
    }

    func testClearingRemovesTheValue() {
        store().save(GameSetup(buyIn: 25, players: 6, availableColors: ["White"]))
        store().clear()
        XCTAssertNil(store().load())
    }

    func testUnreadableDataIsDroppedInsteadOfCrashing() {
        defaults.set(Data("not json at all".utf8), forKey: "setup")

        XCTAssertNil(store().load())
        XCTAssertNil(defaults.data(forKey: "setup"), "the bad entry is removed so it isn't re-read forever")
    }

    func testDataInAnOlderShapeIsDroppedToo() {
        defaults.set(Data(#"{"buyIn": 25}"#.utf8), forKey: "setup")
        XCTAssertNil(store().load())
    }
}

final class GameSetupTests: XCTestCase {
    func testColoursAreKeptInTheCanonicalOrderNoMatterHowTheyWereChosen() {
        let setup = GameSetup(buyIn: 25, players: 6, availableColors: ["Black", "White", "Blue"])
        XCTAssertEqual(setup.colors, ["White", "Blue", "Black"])
        XCTAssertEqual(setup.availableColors, ["Black", "White", "Blue"])
    }

    func testEqualSetupsAreEqual() {
        XCTAssertEqual(
            GameSetup(buyIn: 25, players: 6, availableColors: ["Red", "White"]),
            GameSetup(buyIn: 25, players: 6, availableColors: ["White", "Red"])
        )
    }

    func testASetupSavedBeforeNamesExistedStillOpens() throws {
        let old = #"{"buyIn": 25, "players": 6, "colors": ["White", "Red"]}"#
        let setup = try JSONDecoder().decode(GameSetup.self, from: Data(old.utf8))
        XCTAssertEqual(setup.playerNames, [])
        XCTAssertNil(setup.location)
        XCTAssertEqual(setup.colors, ["White", "Red"])
    }

    func testNamesAndPlaceSurviveBeingSavedAndLoaded() throws {
        let setup = GameSetup(buyIn: 25, players: 3, availableColors: ["White"], playerNames: ["Pranav", "Sam"], location: "Pat's garage")
        let restored = try JSONDecoder().decode(GameSetup.self, from: JSONEncoder().encode(setup))
        XCTAssertEqual(restored, setup)
    }

    func testTheTableAlwaysHasExactlyAsManySeatsAsPlayers() {
        XCTAssertEqual(GameSetup(buyIn: 25, players: 4, availableColors: ["White"], playerNames: ["Pranav", "Sam"]).namesForTable, ["Pranav", "Sam", "", ""])
        XCTAssertEqual(GameSetup(buyIn: 25, players: 2, availableColors: ["White"], playerNames: ["A", "B", "C"]).namesForTable, ["A", "B"])
    }
}

final class RetiredKeysTests: XCTestCase {
    func testKeysFromTheSingleGameEraAreCleanedUpAndNothingElseIs() {
        let suite = "tests.retired.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("no defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }

        for key in ["store.activeSession.v1", "store.lastGame.v1", "store.lastResult.v1", "store.pendingSaves.v1", "store.gameSetup.v1"] {
            defaults.set(Data("x".utf8), forKey: key)
        }
        Stores.removeRetiredKeys(defaults: defaults)

        XCTAssertNil(defaults.data(forKey: "store.activeSession.v1"))
        XCTAssertNil(defaults.data(forKey: "store.lastGame.v1"))
        XCTAssertNil(defaults.data(forKey: "store.lastResult.v1"))
        XCTAssertNil(defaults.data(forKey: "store.pendingSaves.v1"))
        XCTAssertNotNil(defaults.data(forKey: "store.gameSetup.v1"), "what the next night starts from is kept")
    }
}
