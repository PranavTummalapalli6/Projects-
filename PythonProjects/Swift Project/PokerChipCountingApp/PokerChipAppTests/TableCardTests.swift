//
//  TableCardTests.swift
//  PokerChipAppTests
//
//  The card for the middle of the table: what it says, that it never carries a
//  name or a place, that a picture and a PDF of it can really be made, and that
//  the app is portrait again once it has gone.
//

import XCTest
import UIKit
@testable import PokerChipApp

final class TableCardContentTests: XCTestCase {
    private func night(counts: [String: Int]? = ["White": 20, "Red": 8], blinds: Blinds? = Blinds(smallMinor: 25, bigMinor: 50)) -> GameNight {
        GameNight(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tzIdentifier: "UTC",
            defaultBuyInMinor: 2_500,
            blinds: blinds,
            location: "Sam's kitchen",
            colors: ["Red", "White"],
            denominationsMinor: ["White": 25, "Red": 100],
            startingCounts: counts,
            players: [PlayerLedger(id: UUID(), name: "Ann", buyIns: [], cashOutMinor: nil, cashedOutAt: nil)],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testRowsAreInChipOrderWhateverOrderTheNightStoredThem() throws {
        let content = try XCTUnwrap(TableCardContent(night: night()))
        XCTAssertEqual(content.rows.map(\.color), ["White", "Red"])
        XCTAssertEqual(content.rows.map(\.valueCents), [25, 100])
        XCTAssertEqual(content.rows.map(\.count), [20, 8])
    }

    func testTheStackLineSaysWhatEachPlayerStartsWith() throws {
        let content = try XCTUnwrap(TableCardContent(night: night()))
        XCTAssertEqual(content.chipsPerPlayer, 28)
        XCTAssertEqual(content.stackLine, "Each player starts with 28 chips · $25.00")
        XCTAssertEqual(content.blindsLine, "Blinds $0.25 / $0.50")
    }

    func testWithoutARecordedStackItSaysTheBuyInInstead() throws {
        let content = try XCTUnwrap(TableCardContent(night: night(counts: nil, blinds: nil)))
        XCTAssertNil(content.chipsPerPlayer)
        XCTAssertEqual(content.stackLine, "Buy-in $25.00")
        XCTAssertNil(content.blindsLine)
    }

    func testAColourWithoutACountMeansNoClaimAboutTheTotal() throws {
        let content = try XCTUnwrap(TableCardContent(night: night(counts: ["White": 20])))
        XCTAssertNil(content.chipsPerPlayer)
        XCTAssertEqual(content.rows.map(\.count), [20, nil])
    }

    func testANightWithNoChipValuesHasNoCard() {
        var empty = night()
        empty.denominationsMinor = [:]
        XCTAssertNil(TableCardContent(night: empty))
    }

    func testTheCardCarriesNoNamesPlacesOrDates() throws {
        let content = try XCTUnwrap(TableCardContent(night: night()))
        let everything = ([content.stackLine, content.blindsLine ?? ""] + content.rows.map(\.color)).joined(separator: " ")
        XCTAssertFalse(everything.contains("Ann"))
        XCTAssertFalse(everything.contains("kitchen"))
        XCTAssertFalse(everything.contains("2023"))
    }

    @MainActor
    func testASuggestionBecomesTheSameCard() async throws {
        let outcome = await SuggestedViewModel.outcome(for: GameSetup(buyIn: 25, players: 6, availableColors: Set(allChipColors)))
        guard case .ready(let options) = outcome, let suggestion = options.first else { return XCTFail("expected a suggestion") }
        let content = TableCardContent(suggestion: suggestion, blinds: Blinds(smallMinor: 25, bigMinor: 50))
        XCTAssertEqual(content.rows.map(\.color), allChipColors)
        XCTAssertEqual(content.buyInCents, 2_500)
        XCTAssertEqual(content.chipsPerPlayer, suggestion.totalChips)
        XCTAssertEqual(content.rows.reduce(0) { $0 + $1.valueCents * ($1.count ?? 0) }, 2_500)
    }

    func testAnotherCurrencyIsShownInItsOwnSymbol() throws {
        var euro = night()
        euro.currency = "EUR"
        let content = try XCTUnwrap(TableCardContent(night: euro))
        XCTAssertTrue(content.stackLine.contains("€"), content.stackLine)
    }
}

@MainActor
final class TableCardExportTests: XCTestCase {
    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tablecard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let content = TableCardContent(
        rows: [
            .init(color: "White", valueCents: 5, count: 20),
            .init(color: "Red", valueCents: 10, count: 12),
            .init(color: "Blue", valueCents: 25, count: 8),
            .init(color: "Green", valueCents: 50, count: 4),
            .init(color: "Black", valueCents: 100, count: 2),
        ],
        buyInCents: 2_500,
        blinds: Blinds(smallMinor: 25, bigMinor: 50),
        currencyCode: "USD"
    )

    func testAPictureAndAPDFAreWritten() throws {
        let files = try XCTUnwrap(TableCardExporter.export(content, directory: directory))

        let png = try Data(contentsOf: files.png)
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "a PNG")
        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertEqual(image.size.width * image.scale, 2_400, accuracy: 1)
        XCTAssertEqual(image.size.height * image.scale, 1_350, accuracy: 1)

        let pdf = try Data(contentsOf: files.pdf)
        XCTAssertEqual(String(decoding: pdf.prefix(5), as: UTF8.self), "%PDF-", "a PDF")
        XCTAssertGreaterThan(pdf.count, 1_000)
    }

    func testTheFilesAreNamedForWhatTheyAre() throws {
        let files = try XCTUnwrap(TableCardExporter.export(content, directory: directory))
        XCTAssertEqual(files.png.lastPathComponent, "Chip values.png")
        XCTAssertEqual(files.pdf.lastPathComponent, "Chip values.pdf")
    }

    func testExportingAgainReplacesTheFilesInsteadOfFailing() throws {
        _ = try XCTUnwrap(TableCardExporter.export(content, directory: directory))
        let again = try XCTUnwrap(TableCardExporter.export(content, directory: directory))
        XCTAssertTrue(FileManager.default.fileExists(atPath: again.png.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: again.pdf.path))
    }

    func testOneColourAndNoBlindsStillMakesACard() throws {
        let single = TableCardContent(rows: [.init(color: "White", valueCents: 25, count: 100)], buyInCents: 2_500, blinds: nil, currencyCode: "USD")
        XCTAssertNotNil(TableCardExporter.export(single, directory: directory))
    }

    func testAnUnwritableFolderIsANilNotACrash() {
        let nowhere = directory.appendingPathComponent("missing/inside")
        XCTAssertNil(TableCardExporter.export(content, directory: nowhere))
    }
}

@MainActor
final class OrientationLockTests: XCTestCase {
    override func tearDown() {
        OrientationLock.restorePortrait()
        super.tearDown()
    }

    func testTheAppIsPortraitUntilTheCardAsksOtherwise() {
        OrientationLock.restorePortrait()
        XCTAssertEqual(OrientationLock.current, .portrait)
    }

    func testTheCardWidensItToLandscapeAndPutsItBack() {
        OrientationLock.allowLandscape()
        XCTAssertEqual(OrientationLock.current, .landscape)
        XCTAssertFalse(OrientationLock.current.contains(.portrait))
        OrientationLock.restorePortrait()
        XCTAssertEqual(OrientationLock.current, .portrait)
    }

    func testTheAppDelegateAnswersWithWhateverIsCurrent() {
        let delegate = AppDelegate()
        OrientationLock.allowLandscape()
        XCTAssertEqual(delegate.application(UIApplication.shared, supportedInterfaceOrientationsFor: nil), .landscape)
        OrientationLock.restorePortrait()
        XCTAssertEqual(delegate.application(UIApplication.shared, supportedInterfaceOrientationsFor: nil), .portrait)
    }
}
