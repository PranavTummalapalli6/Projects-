//
//  PokerChipAppUITestsLaunchTests.swift
//  PokerChipAppUITests
//
//  Created by Pranav on 11/11/24.
//

import XCTest

final class PokerChipAppUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-ResetState"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["home.newGame"].waitForExistence(timeout: 8))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
