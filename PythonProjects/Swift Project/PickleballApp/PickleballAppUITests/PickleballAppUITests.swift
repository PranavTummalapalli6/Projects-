import XCTest

/// Runs against the offline demo backend at a fixed location next to "Laurel Creek Park"
/// (see AppEnvironment `-uiTesting`). No network or permission prompts involved.
final class PickleballAppUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    func testMapShowsRecommendationsAndFacilitySheet() {
        // On arrival the one-tap question takes the bottom slot; "Not now" reveals the recommendations.
        let dismiss = app.buttons["promptDismiss"]
        if dismiss.waitForExistence(timeout: 6) { dismiss.tap() }
        let strip = app.descendants(matching: .any)["recommendationStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10), "recommendation cards should appear")
        let marker = app.buttons["marker_Laurel Creek Park"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        marker.tap()
        XCTAssertTrue(app.buttons["directionsButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detailsButton"].exists)
        app.buttons["detailsButton"].tap()
        XCTAssertTrue(app.staticTexts["Availability"].waitForExistence(timeout: 5))
    }

    func testArrivalPromptIsOneTap() {
        let card = app.descendants(matching: .any)["promptCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "arriving at a court shows one contextual question")
        let answer = app.buttons["answer_none"].exists ? app.buttons["answer_none"] : app.buttons["answer_courts_open"]
        XCTAssertTrue(answer.waitForExistence(timeout: 3))
        answer.tap()
        XCTAssertTrue(app.staticTexts["Thanks!"].waitForExistence(timeout: 5))
    }

    func testAddCourtMinimalFlow() {
        let dismiss = app.buttons["promptDismiss"]
        if dismiss.waitForExistence(timeout: 6) { dismiss.tap() }
        let add = app.buttons["addCourtButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let useSpot = app.buttons["useThisSpot"]
        XCTAssertTrue(useSpot.waitForExistence(timeout: 5))
        useSpot.tap()
        app.buttons["2"].tap()
        app.buttons["submitCourt"].tap()
        let notDuplicate = app.buttons["notDuplicate"]
        if notDuplicate.waitForExistence(timeout: 3) { notDuplicate.tap() }
        XCTAssertTrue(app.descendants(matching: .any)["addCourtDone"].waitForExistence(timeout: 8))
    }

    func testSearchWorksWithoutLocation() {
        app.buttons["searchButton"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Oak Hollow")
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Oak Hollow'")).firstMatch.waitForExistence(timeout: 5))
    }
}
