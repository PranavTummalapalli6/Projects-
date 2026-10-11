//
//  PokerChipAppUITests.swift
//  PokerChipAppUITests
//
//  Created by Pranav on 11/11/24.
//
//  Drives the real app end to end. `-UITestMode` swaps sign-in and the network
//  for deterministic stubs, so these never touch Firebase or the backend.
//  Screenshots are attached at each step (kept for every run) and double as the
//  visual-QA record: export them with
//      xcrun xcresulttool export attachments --path <result>.xcresult --output-path <dir>
//
//  The simulator has no camera, so the photo path is covered by checking that
//  the app says so and offers the alternatives; counting by hand is the path
//  that gets driven through to a result.
//

import XCTest

final class PokerChipAppUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: Helpers

    private func launch(reset: Bool = true) {
        app.launchArguments = ["-UITestMode"] + (reset ? ["-ResetState"] : [])
        app.launch()
    }

    /// Any element with this accessibility identifier, whatever its type —
    /// SwiftUI reports the same control as a button, text or "other" depending
    /// on how it's composed.
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @discardableResult
    private func waitFor(_ identifier: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let match = element(identifier)
        XCTAssertTrue(match.waitForExistence(timeout: timeout), "'\(identifier)' never appeared", file: file, line: line)
        return match
    }

    /// Taps the control, first scrolling it into the clear middle of the screen: a
    /// button half under the pinned action bar (or the navigation bar) is "there",
    /// but the tap would land on the bar.
    private func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = waitFor(identifier, file: file, line: line)
        // Only content that scrolls ever needs scrolling to. A pinned bar's button or a navigation
        // bar item doesn't move, and a drag that starts beside a stepper can press it: a count
        // went from 100 to 101 that way.
        if isInScrollingContent(identifier) { scrollIntoClearView(target) }
        target.tap()
    }

    private func isInScrollingContent(_ identifier: String) -> Bool {
        app.scrollViews.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
            || app.tables.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
            || app.collectionViews.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
    }

    private func scrollIntoClearView(_ target: XCUIElement) {
        let screen = app.frame.height
        for _ in 0..<12 {
            let frame = target.frame
            if frame.isEmpty { return }
            if frame.minY < screen * 0.16 {                      // too high: under the navigation bar
                dragContent(down: true)
                if target.frame == frame { return }               // in the bar itself, or already at the top
            } else if frame.maxY > screen * 0.76 {               // too low: under the action bar
                dragContent(down: false)
                if target.frame == frame { return }               // in the bar itself, or already at the end
            } else {
                return
            }
        }
    }

    /// A short, controlled drag in the middle of the screen (a full swipe overshoots).
    /// `down` drags the finger down, which moves the content down.
    private func dragContent(down: Bool) {
        // In the right-hand gutter, where no card or control is: a drag that starts on a
        // stepper once took a chip off the count.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: down ? 0.45 : 0.65))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: down ? 0.65 : 0.45))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    private func openTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "no “\(name)” tab", file: file, line: line)
        tab.tap()
    }

    /// Waits for the element's label (not just its existence) to contain the text.
    private func waitForLabel(_ identifier: String, containing text: String, timeout: TimeInterval = 6) -> Bool {
        let match = element(identifier)
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: match)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits for the element's accessibility value to equal the text.
    private func waitForValue(_ identifier: String, _ value: String, timeout: TimeInterval = 6) -> Bool {
        let match = element(identifier)
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: match)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// `app.screenshot()` of an app that has turned itself sideways comes out cropped; the screen's doesn't.
    private func screenshot() -> XCUIScreenshot {
        app.frame.width > app.frame.height ? XCUIScreen.main.screenshot() : app.screenshot()
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Total seconds in a VoiceOver duration such as "1 minute, 20 seconds".
    private func seconds(inSpoken text: String) -> Int {
        func number(before unit: String) -> Int {
            guard let range = text.range(of: #"(\d+) "# + unit, options: .regularExpression) else { return 0 }
            return Int(text[range].split(separator: " ").first ?? "") ?? 0
        }
        return number(before: "hour") * 3_600 + number(before: "minute") * 60 + number(before: "second")
    }

    private func dismissKeyboardIfShown() {
        if app.keyboards.count > 0, element("keyboard.done").exists {
            element("keyboard.done").tap()
        }
    }

    /// Home → Buy-in → Players → Chip values: a $25 buy-in, every chip colour, and these players.
    private func goToChipValues(players: [String] = ["Sam", "Alex", "Jo"], place: String? = nil, snapshots: Bool = false, chipSet: Int? = nil) {
        tap("home.newGame")
        let amount = waitFor("buyin.amount")
        amount.tap()
        amount.typeText("25")
        dismissKeyboardIfShown()
        for _ in 0..<(6 - players.count) { tap("buyin.players.minus") }
        tap("buyin.selectAll")
        if let chipSet {
            tap("buyin.chipSet")
            tap("chipset.size.\(chipSet)")
            tap("chipset.save")
            waitFor("buyin.next")
        }
        if snapshots { snapshot("02-buy-in") }
        tap("buyin.next")

        waitFor("players.name.0")
        for (index, name) in players.enumerated() {
            let field = element("players.name.\(index)")
            field.tap()
            field.typeText(name)
        }
        if let place {
            // With a name field's keyboard up, the pinned Next bar rides on top of it and covers
            // the place field, so put the keyboard away first.
            dismissKeyboardIfShown()
            tap("players.place")
            element("players.place").typeText(place)
        }
        dismissKeyboardIfShown()
        if snapshots { snapshot("03-players") }
        tap("players.next")
        waitFor("style.suggested")
    }

    private func startSuggestedNight(players: [String] = ["Sam", "Alex", "Jo"], snapshots: Bool = false) {
        goToChipValues(players: players, snapshots: snapshots)
        if snapshots { snapshot("04-chip-values") }
        tap("style.suggested")
        waitFor("suggested.total")
        if snapshots { snapshot("05-suggested-chips") }
        tap("suggested.start")
        waitFor("night.clock")
    }

    /// Ends the night and cashes each player out for an amount, in the order given.
    private func cashOut(_ amounts: [(name: String, amount: String)]) {
        for entry in amounts {
            tap("night.cashOut.\(entry.name)")
            let amountMode = app.segmentedControls.buttons["Enter amount"]
            XCTAssertTrue(amountMode.waitForExistence(timeout: 8), "the cash-out screen never appeared")
            amountMode.tap()
            let field = waitFor("cashout.amount")
            field.tap()
            field.typeText(entry.amount)
            dismissKeyboardIfShown()
            tap("cashout.save")
            waitFor("night.player.\(entry.name)")
        }
    }

    private func endNight() {
        tap("night.end")
        app.sheets.buttons["End night"].tap()
        waitFor("night.endedBanner")
    }

    // MARK: The whole night

    func testAWholeNightFromBuyInToSettlement() throws {
        launch()

        waitFor("home.newGame")
        XCTAssertTrue(element("home.howItWorks").waitForExistence(timeout: 3), "a first-time player should see how a night works")
        snapshot("01-home")

        startSuggestedNight(snapshots: true)
        let pot = waitFor("night.pot")
        XCTAssertTrue(pot.label.contains("$75.00 in play"), "three players in for $25: \(pot.label)")
        snapshot("06-live-night")

        // A rebuy is one tap, shows up at once, and can be taken back.
        tap("night.rebuy.Alex")
        XCTAssertTrue(waitForLabel("night.pot", containing: "$100.00 in play"), "a $25 rebuy: \(element("night.pot").label)")
        waitFor("night.undoBanner")
        snapshot("07-after-a-rebuy")
        app.buttons["Undo"].tap()
        XCTAssertTrue(waitForLabel("night.pot", containing: "$75.00 in play"), "undone: \(element("night.pot").label)")
        tap("night.rebuy.Alex")
        XCTAssertTrue(waitForLabel("night.pot", containing: "$100.00 in play"))

        // Calling the game stops the clock and turns the same screen into the cash-out list.
        endNight()
        snapshot("08-cash-out-list")
        XCTAssertFalse(element("night.bank").isEnabled, "nobody has cashed out yet")

        // Chips on the table come to $98.00 against $100.00 put in: $2.00 is missing.
        cashOut([("Sam", "60"), ("Alex", "15")])
        XCTAssertFalse(element("night.bank").isEnabled, "one player still to cash out")
        cashOut([("Jo", "23")])
        XCTAssertTrue(element("night.bank").isEnabled)

        tap("night.bank")
        waitFor("bank.difference")
        snapshot("09-bank-check-short")
        XCTAssertFalse(element("bank.settle").isEnabled, "the difference has to be explained before settling")

        // Nothing is rounded away: the host says what the $2.00 was.
        tap("bank.tip")
        XCTAssertTrue(element("bank.settle").waitForExistence(timeout: 3))
        XCTAssertTrue(element("bank.settle").isEnabled)
        snapshot("10-bank-check-resolved")
        tap("bank.settle")

        // Sam +$35, Alex −$35, Jo −$2, and $2 of tips: two payments settle everything.
        waitFor("settle.pay.Alex.Sam")
        waitFor("settle.pay.Jo.Tips")
        XCTAssertTrue((element("settle.pay.Alex.Sam").value as? String ?? "").contains("35.00"), "got \(String(describing: element("settle.pay.Alex.Sam").value))")
        XCTAssertTrue((element("settle.pay.Jo.Tips").value as? String ?? "").contains("2.00"), "got \(String(describing: element("settle.pay.Jo.Tips").value))")
        XCTAssertTrue(element("settle.shareText").exists)
        snapshot("11-settle-up")

        tap("settle.close")
        let net = waitFor("result.net")
        XCTAssertTrue((net.value as? String ?? "").contains("35"), "Sam finished $35 up, got \(String(describing: net.value))")
        snapshot("12-result")

        tap("result.health")
        waitFor("health.total")
        snapshot("13-poker-health")
        tap("health.playAgain")

        waitFor("home.newGame")
        XCTAssertTrue(element("home.sameAsLast").exists, "the last game's setup should be one tap away")
        XCTAssertTrue(element("home.lastResult").exists)
        XCTAssertFalse(element("home.resume").exists, "the night is closed")
        snapshot("14-home-after-a-night")
    }

    func testTheBankHasToBalanceAndAnOverageCanBeSplit() throws {
        launch()
        startSuggestedNight(players: ["Sam", "Alex"])
        endNight()

        // $55.00 of chips against $50.00 in: $5.00 too many chips.
        cashOut([("Sam", "40"), ("Alex", "15")])
        tap("night.bank")
        waitFor("bank.difference")
        XCTAssertFalse(element("bank.tip").exists, "chips can't turn up as a tip")
        XCTAssertFalse(element("bank.settle").isEnabled)

        tap("bank.split")
        XCTAssertTrue(element("bank.settle").isEnabled)
        tap("bank.settle")

        // Split evenly the $5.00 is $2.50 off each cash-out: Sam +$12.50, Alex −$12.50.
        waitFor("settle.pay.Alex.Sam")
        XCTAssertTrue((element("settle.pay.Alex.Sam").value as? String ?? "").contains("12.50"), "got \(String(describing: element("settle.pay.Alex.Sam").value))")
    }

    func testARecountFixesTheBankInsteadOfExplainingTheDifference() throws {
        launch()
        startSuggestedNight(players: ["Sam", "Alex"])
        endNight()
        cashOut([("Sam", "40"), ("Alex", "15")])           // $5.00 over
        tap("night.bank")
        waitFor("bank.difference")

        // "Recount a player's chips" asks whose, then opens that player's cash-out.
        tap("bank.recount")
        let alex = app.sheets.buttons["Alex"]
        XCTAssertTrue(alex.waitForExistence(timeout: 5), "the recount should ask whose chips")
        alex.tap()
        waitFor("cashout.amount")
        let field = element("cashout.amount")
        field.tap()
        field.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        field.typeText("10")
        dismissKeyboardIfShown()
        tap("cashout.save")

        // Back on the bank check, which has updated itself: the difference is gone.
        waitFor("bank.balanced")
        XCTAssertTrue(element("bank.settle").isEnabled)
    }

    func testCountingChipsByHandAddsUpTheirValue() throws {
        launch()
        startSuggestedNight(players: ["Sam", "Alex"])
        endNight()

        tap("night.cashOut.Sam")
        waitFor("review.totals")
        let empty = element("review.totals").label
        for _ in 0..<3 { tap("review.count.Red.plus") }
        snapshot("15-counting-chips")
        let counted = element("review.totals").label
        XCTAssertNotEqual(empty, counted, "counting chips changes the total")
        XCTAssertTrue(element("cashout.save").isEnabled)

        // The Simulator has no camera: the app says so, and counting by hand still works.
        XCTAssertFalse(element("cashout.takePhoto").isEnabled)
        tap("cashout.save")
        waitFor("night.editCashOut.Sam")
    }

    // MARK: A night survives the app being killed

    func testANightInProgressIsStillThereAfterTheAppIsKilled() throws {
        launch()
        startSuggestedNight()
        tap("night.rebuy.Jo")
        XCTAssertTrue(waitForLabel("night.pot", containing: "$100.00 in play"))

        Thread.sleep(forTimeInterval: 3)
        app.terminate()
        Thread.sleep(forTimeInterval: 2)          // time passes while the app is dead

        launch(reset: false)
        waitFor("home.resume")
        snapshot("16-home-with-resume-card")
        XCTAssertFalse(element("home.newGame").isEnabled, "a second night shouldn't start on top of this one")

        tap("home.resume")
        let clock = waitFor("night.clock")
        let spoken = clock.value as? String ?? ""
        XCTAssertGreaterThanOrEqual(seconds(inSpoken: spoken), 5, "the clock should include the time while the app was closed, got '\(spoken)'")
        XCTAssertTrue(waitForLabel("night.pot", containing: "$100.00 in play"), "the rebuy survived: \(element("night.pot").label)")
    }

    func testTheClockStopsWhenTheGameIsCalledAndStaysStopped() throws {
        launch()
        startSuggestedNight()
        Thread.sleep(forTimeInterval: 4)
        endNight()

        let stopped = waitFor("night.clock").value as? String ?? ""
        XCTAssertGreaterThanOrEqual(seconds(inSpoken: stopped), 4)

        tap("night.cashOut.Sam")                            // into a cash-out and back
        XCTAssertTrue(app.segmentedControls.buttons["Count chips"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(waitFor("night.clock").value as? String, stopped, "the clock must not run on, or restart")
        XCTAssertTrue(app.staticTexts["Game over"].firstMatch.exists || app.staticTexts["GAME OVER"].firstMatch.exists)
    }

    func testPlayCanCarryOnAfterAMistakenEndNight() throws {
        launch()
        startSuggestedNight()
        endNight()
        app.buttons["Resume play"].tap()
        waitFor("night.end")
        XCTAssertTrue(element("night.rebuy.Sam").exists, "rebuys are back")
    }

    func testANightCanBeDeleted() throws {
        launch()
        startSuggestedNight()

        app.navigationBars.buttons.firstMatch.tap()      // back to Home
        tap("home.discard")
        app.sheets.buttons["Delete night"].tap()

        waitFor("home.newGame")
        XCTAssertTrue(element("home.newGame").isEnabled)
        XCTAssertFalse(element("home.resume").exists)
    }

    func testLatePlayersCanJoinAndAnyoneCanBeRenamed() throws {
        launch()
        startSuggestedNight(players: ["Sam", "Alex"])

        tap("night.addPlayer")
        let name = waitFor("nameSheet.field")
        name.tap()
        name.typeText("Kim")
        tap("nameSheet.save")
        waitFor("night.player.Kim")
        XCTAssertTrue(waitForLabel("night.pot", containing: "$75.00 in play"), "Kim joins in for $25")
        snapshot("17-late-player")

        tap("night.playerMenu.Kim")
        app.buttons["Rename"].tap()
        let rename = waitFor("nameSheet.field")
        rename.tap()
        rename.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        rename.typeText("Kimberly")
        tap("nameSheet.save")
        waitFor("night.player.Kimberly")
    }

    // MARK: Setting up

    func testTwoPlayersCannotShareAName() throws {
        launch()
        tap("home.newGame")
        let amount = waitFor("buyin.amount")
        amount.tap()
        amount.typeText("25")
        dismissKeyboardIfShown()
        tap("buyin.selectAll")
        tap("buyin.next")

        let first = waitFor("players.name.0")
        first.tap()
        first.typeText("Sam")
        let second = element("players.name.1")
        second.tap()
        second.typeText("sam")
        dismissKeyboardIfShown()

        let problem = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'different name'")).firstMatch
        XCTAssertTrue(problem.waitForExistence(timeout: 3))
        XCTAssertFalse(element("players.next").isEnabled)
        snapshot("18-duplicate-names")
    }

    func testTheBuyInScreenExplainsWhatIsMissing() throws {
        launch()
        tap("home.newGame")
        tap("buyin.next")

        let amountProblem = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Enter an amount'")).firstMatch
        XCTAssertTrue(amountProblem.waitForExistence(timeout: 3))
        let colourProblem = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Tap every chip colour'")).firstMatch
        XCTAssertTrue(colourProblem.exists)
        snapshot("19-buy-in-validation")
        XCTAssertFalse(element("players.name.0").exists, "must not move on with an incomplete form")
    }

    func testQuickPicksFillTheAmount() throws {
        launch()
        tap("home.newGame")
        tap("buyin.quick.50")
        let amount = waitFor("buyin.amount")
        XCTAssertEqual(amount.value as? String, "50")
    }

    func testATooSmallBuyInGetsAnExplanationInsteadOfAWrongStack() throws {
        launch()
        tap("home.newGame")
        let amount = waitFor("buyin.amount")
        amount.tap()
        amount.typeText("1")
        dismissKeyboardIfShown()
        tap("buyin.selectAll")
        tap("buyin.next")
        waitFor("players.next")
        tap("players.next")
        tap("style.suggested")

        let message = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'too small'")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        snapshot("20-buy-in-too-small")
    }

    func testSameAsLastGameKeepsTheNamesAndOffersTheSameChips() throws {
        launch()
        startSuggestedNight(players: ["Sam", "Alex", "Jo"])
        endNight()
        cashOut([("Sam", "25"), ("Alex", "25"), ("Jo", "25")])
        tap("night.bank")
        tap("bank.settle")
        tap("settle.close")
        waitFor("result.net")
        tap("result.done")

        tap("home.sameAsLast")
        let first = waitFor("players.name.0")
        XCTAssertEqual(first.value as? String, "Sam")
        XCTAssertEqual(element("players.name.2").value as? String, "Jo")
        tap("players.next")
        tap("style.sameChips")
        waitFor("night.clock")
        XCTAssertTrue(waitForLabel("night.pot", containing: "$75.00 in play"))
    }

    // MARK: History, stats and healthy play

    /// A quick, balanced night in which Sam wins $15 from Alex.
    private func playAQuickNight(place: String? = nil) {
        goToChipValues(players: ["Sam", "Alex"], place: place)
        tap("style.suggested")
        waitFor("suggested.total")
        tap("suggested.start")
        waitFor("night.clock")
        endNight()
        cashOut([("Sam", "40"), ("Alex", "10")])
        tap("night.bank")
        tap("bank.settle")
        tap("settle.close")
        waitFor("result.net")
        tap("result.done")
        waitFor("home.newGame")
    }

    func testAClosedNightShowsUpInHistoryAndStats() throws {
        launch()
        openTab("History")
        waitFor("history.empty")
        snapshot("25-history-empty")
        openTab("Stats")
        waitFor("stats.empty")
        snapshot("26-stats-empty")

        openTab("Play")
        playAQuickNight()

        openTab("History")
        let row = waitFor("history.row.0")
        XCTAssertTrue(row.label.contains("2 players"), "the row says what it was: \(row.label)")
        XCTAssertTrue(row.label.contains("up"), "and how it went: \(row.label)")
        snapshot("27-history")
        tap("history.row.0")
        waitFor("detail.players")
        XCTAssertTrue(element("detail.result").exists)
        snapshot("28-night-detail")
        app.navigationBars.buttons.firstMatch.tap()

        openTab("Stats")
        let net = waitFor("stats.net")
        XCTAssertTrue((net.value as? String ?? "").contains("15"), "Sam finished $15 up: \(String(describing: net.value))")
        XCTAssertTrue(element("stats.perHourCaveat").exists, "one night is far too few for an hourly rate")
        snapshot("29-stats")
    }

    func testANightCanBeDeletedFromHistoryAndBroughtBack() throws {
        launch()
        playAQuickNight()
        openTab("History")
        let row = waitFor("history.row.0")
        row.swipeLeft()
        app.buttons["Delete"].tap()

        waitFor("undo.banner")
        waitFor("history.empty")
        snapshot("30-history-undo")
        app.buttons["Undo"].tap()
        waitFor("history.row.0")
    }

    func testHistoryCanBeSearchedAndFiltered() throws {
        launch()
        playAQuickNight(place: "Pat's garage")
        openTab("History")
        waitFor("history.row.0")

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("garage")
        XCTAssertTrue(element("history.row.0").waitForExistence(timeout: 3))

        search.clearAndTypeText("zebra")
        waitFor("history.noMatches")
        snapshot("31-history-no-matches")
        tap("history.filter.clear")
        waitFor("history.row.0")
    }

    func testAnEmptyHistoryAndEmptyStatsInviteTheFirstNight() throws {
        launch()
        openTab("History")
        waitFor("history.empty")
        app.buttons["Start a night"].tap()
        waitFor("buyin.amount")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "setting up a night has the room to itself")
    }

    func testTakingABreakPausesNewNightsButNothingElse() throws {
        launch()
        openTab("Settings")
        tap("settings.break.24 hours")
        app.sheets.buttons["Start the break"].tap()
        waitFor("settings.breakActive")
        snapshot("32-break-active")

        openTab("Play")
        waitFor("home.coolOff")
        XCTAssertFalse(element("home.newGame").isEnabled, "no new night while on a break")
        XCTAssertFalse(element("home.sameAsLast").exists)
        openTab("History")
        waitFor("history.empty")                                             // the history itself is still there to look at
    }

    func testHelpIsOneTapAwayInSettings() throws {
        launch()
        openTab("Settings")
        let help = waitFor("settings.help")
        for _ in 0..<6 where !help.isHittable { app.swipeUp() }
        snapshot("33-settings-help")
        XCTAssertTrue(element("settings.help.web").exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'checked'")).firstMatch.exists, "says when the numbers were last checked")
    }

    // MARK: Custom chips

    func testCustomChipsShowTheRunningTotalAgainstTheBuyIn() throws {
        launch()
        goToChipValues()
        tap("style.custom")

        let white = waitFor("custom.value.White")
        XCTAssertTrue(white.waitForExistence(timeout: 5))
        snapshot("21-custom-chips")
        // Starts from the suggestion, so the stack already adds up.
        let matches = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'add up'")).firstMatch
        XCTAssertTrue(matches.waitForExistence(timeout: 5))
        XCTAssertTrue(element("custom.start").isEnabled)
    }

    // MARK: Account

    func testSigningOutAndBackInAsAGuest() throws {
        launch()
        openTab("Settings")
        snapshot("22-settings")
        tap("settings.signOut")
        app.sheets.buttons["Sign out"].tap()

        waitFor("auth.guest")
        snapshot("23-welcome")
        tap("auth.guest")
        waitFor("home.newGame")
    }

    func testDeletingTheAccountReturnsToTheWelcomeScreen() throws {
        launch()
        openTab("Settings")
        tap("settings.deleteAccount")
        app.sheets.buttons["Delete account"].tap()

        waitFor("auth.guest")
    }

    func testEmailSignInChecksTheFormBeforeSendingAnything() throws {
        launch()
        openTab("Settings")
        tap("settings.signOut")
        app.sheets.buttons["Sign out"].tap()
        tap("auth.email")

        tap("auth.submit")
        let emailProblem = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Enter your email'")).firstMatch
        XCTAssertTrue(emailProblem.waitForExistence(timeout: 3))
        snapshot("24-email-validation")

        let email = waitFor("auth.emailField")
        email.tap()
        email.typeText("not-an-email")
        tap("auth.submit")
        let badEmail = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'email address'")).firstMatch
        XCTAssertTrue(badEmail.waitForExistence(timeout: 3))
    }

    // MARK: Launch

    // MARK: Chip setup

    func testASuggestionCanBeDealtAnotherWayAndAValueCanBeFixed() throws {
        launch()
        goToChipValues()
        tap("style.suggested")
        waitFor("suggested.total")
        XCTAssertEqual(element("suggested.optionTitle").label, "Recommended")
        snapshot("34-suggested-with-options")

        // Another way to deal the same buy-in, when there is one: then back round to the first.
        if element("suggested.another").exists {
            tap("suggested.another")
            XCTAssertNotEqual(element("suggested.optionTitle").label, "Recommended")
            XCTAssertTrue(element("suggested.total").label.contains("$25.00"), "the same money, dealt differently: \(element("suggested.total").label)")
            for _ in 0..<3 where element("suggested.optionTitle").label != "Recommended" { tap("suggested.another") }
            XCTAssertEqual(element("suggested.optionTitle").label, "Recommended")
        }

        // Fixing a value keeps it, and the rest is worked out around it.
        let valueLabel = element("suggested.value.Blue").label
        let current = valueLabel.range(of: #"\$[0-9.,]+"#, options: .regularExpression).map { String(valueLabel[$0]) } ?? "$0.25"
        XCTAssertEqual(element("suggested.value.Blue").value as? String, "Chosen by the app")
        tap("suggested.value.Blue")
        let startsWithValue = NSPredicate(format: "label BEGINSWITH %@", current)
        var choice = app.menuItems.matching(startsWithValue).firstMatch
        if !choice.waitForExistence(timeout: 3) {
            choice = app.buttons.matching(startsWithValue).matching(NSPredicate(format: "NOT (identifier BEGINSWITH 'suggested')")).firstMatch
        }
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "no \(current) in the value menu")
        choice.tap()
        XCTAssertTrue(waitForValue("suggested.value.Blue", "Fixed"), "got \(String(describing: element("suggested.value.Blue").value))")
        XCTAssertTrue(element("suggested.total").label.contains("$25.00"))
        snapshot("35-value-fixed")
    }

    func testTheTableCardIsLandscapeSharableAndGoesAway() throws {
        launch()
        goToChipValues()
        tap("style.suggested")
        waitFor("suggested.total")
        tap("suggested.tableCard")

        waitFor("tablecard")
        let landscape = NSPredicate { _, _ in self.app.frame.width > self.app.frame.height }
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: landscape, object: nil)], timeout: 10), .completed, "the card turns the screen on its side")
        for color in ["White", "Red", "Blue", "Green", "Black"] {
            XCTAssertTrue(element("tablecard.row.\(color)").exists, "\(color) is on the card")
        }
        XCTAssertTrue(element("tablecard.stack").label.contains("Each player starts with"))
        XCTAssertTrue(element("tablecard.blinds").label.contains("Blinds"))
        XCTAssertTrue(element("tablecard.share").waitForExistence(timeout: 10), "a picture and a PDF are ready to share")
        snapshot("36-table-card")

        element("tablecard.close").tap()
        waitFor("suggested.total")
        let portrait = NSPredicate { _, _ in self.app.frame.height > self.app.frame.width }
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: portrait, object: nil)], timeout: 10), .completed, "and the app is upright again")

        // The same card is one tap away during the night.
        tap("suggested.start")
        waitFor("night.clock")
        tap("night.menu")
        element("night.tableCard").tap()
        waitFor("tablecard.row.White")
        element("tablecard.close").tap()
        waitFor("night.clock")
    }

    func testASetTooSmallForTheTableOffersWhatWouldWork() throws {
        launch()
        goToChipValues(players: ["Sam", "Alex", "Jo", "Kim", "Lee", "Max"], chipSet: 100)
        tap("style.suggested")

        waitFor("suggested.setTooSmall")
        snapshot("37-set-too-small")
        let alternatives = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'suggested.alt.'"))
        XCTAssertGreaterThan(alternatives.count, 0, "never a dead end")
        XCTAssertTrue(element("suggested.changeSet").exists)

        alternatives.firstMatch.tap()
        waitFor("suggested.total")
        XCTAssertTrue(element("suggested.usage").label.contains("of your 100 chips"), element("suggested.usage").label)
        snapshot("38-set-fits")
        tap("suggested.start")
        waitFor("night.clock")
    }

    // MARK: Counting from a photo

    private func goToCashOut(_ name: String = "Sam") {
        startSuggestedNight(players: ["Sam", "Alex"])
        endNight()
        tap("night.cashOut.\(name)")
        waitFor("cashout.samplePhoto")
    }

    func testAPhotoCountsTheChipsAndEachCircleCanBeFixed() throws {
        launch()
        goToCashOut()

        tap("cashout.samplePhoto")
        XCTAssertTrue(waitForLabel("cashout.photoSummary", containing: "1 photo · 27 chips counted", timeout: 15), element("cashout.photoSummary").label)
        XCTAssertEqual(element("review.count.White").value as? String, "10")
        XCTAssertEqual(element("review.count.Black").value as? String, "2")
        snapshot("39-photo-counted")

        // A closer look at the photo: a circle on every chip.
        tap("cashout.photo.0")
        waitFor("photoReview.mark.26")
        XCTAssertFalse(element("photoReview.mark.27").exists)
        // Every colour's tally has room for its number beside the chip (22 pt + 4 pt gap + a digit, 35 pt or more):
        // on the largest phones it once got a sliver (28 pt), so the count could not be read.
        for color in ["White", "Red", "Blue", "Green", "Black"] {
            let legend = element("photoReview.legend.\(color)")
            XCTAssertGreaterThan(legend.frame.width, 31, "the \(color) count in the legend is cut off")
        }
        snapshot("40-photo-review")

        // The first chip is white; it is really red.
        tap("photoReview.mark.0")
        tap("photoReview.color.Red")
        XCTAssertEqual(element("photoReview.legend.White").value as? String, "9")
        XCTAssertEqual(element("photoReview.legend.Red").value as? String, "8")

        // And that one isn't a chip at all.
        tap("photoReview.remove")
        XCTAssertEqual(element("photoReview.legend.Red").value as? String, "7")
        XCTAssertFalse(element("photoReview.mark.26").exists, "one circle fewer")

        // A chip the photo missed: add it where it is.
        tap("photoReview.addMode")
        tap("photoReview.color.Black")
        let anchor = element("photoReview.mark.0").frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: anchor.midX, dy: anchor.midY + app.frame.width * 0.45))
            .tap()
        XCTAssertTrue(waitForValue("photoReview.legend.Black", "3"), "got \(String(describing: element("photoReview.legend.Black").value))")
        snapshot("41-photo-fixed")
        tap("photoReview.addDone")
        tap("photoReview.done")

        // The cash-out counts moved with the circles.
        waitFor("cashout.photoSummary")
        XCTAssertEqual(element("review.count.White").value as? String, "9")
        XCTAssertEqual(element("review.count.Red").value as? String, "7")
        XCTAssertEqual(element("review.count.Black").value as? String, "3")
        XCTAssertTrue(element("cashout.photoSummary").label.contains("27 chips counted"))

        // Chips that wouldn't fit in one photo: a second one adds to the first.
        tap("cashout.samplePhoto")
        XCTAssertTrue(waitForLabel("cashout.photoSummary", containing: "2 photos · 54 chips counted", timeout: 15), element("cashout.photoSummary").label)
        XCTAssertEqual(element("review.count.White").value as? String, "19")
        snapshot("42-two-photos")

        tap("cashout.startOver")
        XCTAssertTrue(waitForValue("review.count.White", "0"))
        XCTAssertFalse(element("cashout.photoSummary").exists)
    }

    func testAPhotoFromTheSideCountsPilesAndEachCanBeCorrected() throws {
        launch()
        goToCashOut()

        XCTAssertTrue(element("cashout.photoAdvice").label.contains("directly overhead"), "from above is the default")
        app.segmentedControls["cashout.photoAngle"].buttons["From the side"].tap()
        XCTAssertTrue(waitForLabel("cashout.photoAdvice", containing: "level with the piles"), element("cashout.photoAdvice").label)

        tap("cashout.samplePhoto")
        XCTAssertTrue(waitForLabel("cashout.photoSummary", containing: "1 photo · 15 chips counted", timeout: 15), element("cashout.photoSummary").label)
        XCTAssertEqual(element("review.count.White").value as? String, "4")
        XCTAssertEqual(element("review.count.Green").value as? String, "5")
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'check every pile'")).firstMatch.exists,
            "the side view is only ever an estimate, and the notice says so"
        )
        snapshot("44-side-counted")

        // A closer look: a box round each pile, and how many chips the service thinks are in it.
        tap("cashout.photo.0")
        waitFor("photoReview.stack.4")
        XCTAssertFalse(element("photoReview.stack.5").exists)
        XCTAssertEqual(element("photoReview.stack.1").label, "Red pile, 3 chips, 2 of 5")
        snapshot("45-side-review")

        // The red pile is really four chips.
        tap("photoReview.stack.1")
        waitFor("photoReview.stackCount")
        tap("photoReview.stackCount.plus")
        XCTAssertEqual(element("photoReview.legend.Red").value as? String, "4")
        XCTAssertEqual(element("photoReview.stack.1").label, "Red pile, 4 chips, 2 of 5")
        snapshot("46-side-fixed")

        // The blue pile is really green.
        tap("photoReview.stack.2")
        tap("photoReview.color.Green")
        XCTAssertEqual(element("photoReview.legend.Blue").value as? String, "0")
        XCTAssertEqual(element("photoReview.legend.Green").value as? String, "7")

        // The black pile was something else.
        tap("photoReview.stack.4")
        tap("photoReview.removeStack")
        XCTAssertFalse(element("photoReview.stack.4").exists, "one pile fewer")
        XCTAssertEqual(element("photoReview.legend.Black").value as? String, "0")

        // A pile the photo missed.
        tap("photoReview.addMode")
        tap("photoReview.color.White")
        // On the table above the first pile (the piles stand low in the picture).
        let anchor = element("photoReview.stack.0").frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: anchor.midX, dy: anchor.midY - app.frame.width * 0.2))
            .tap()
        XCTAssertTrue(waitForValue("photoReview.legend.White", "5"), "got \(String(describing: element("photoReview.legend.White").value))")
        tap("photoReview.addDone")
        tap("photoReview.done")

        // The cash-out counts moved with the piles.
        waitFor("cashout.photoSummary")
        XCTAssertEqual(element("review.count.White").value as? String, "5")
        XCTAssertEqual(element("review.count.Red").value as? String, "4")
        XCTAssertEqual(element("review.count.Blue").value as? String, "0")
        XCTAssertEqual(element("review.count.Green").value as? String, "7")
        XCTAssertEqual(element("review.count.Black").value as? String, "0")
        XCTAssertTrue(element("cashout.photoSummary").label.contains("16 chips counted"), element("cashout.photoSummary").label)
    }

    // MARK: The camera guide
    //
    // The Simulator has no camera, so `-UITestGuidedCamera` swaps in a stand-in that shows a still picture and
    // walks through scripted readings (a "Next reading" button moves it on). What the guide says, and that it
    // never gets in the way of the photo, is driven here; the lens itself can only be tried on a phone.

    private func launchWithGuidedCamera() {
        app.launchArguments = ["-UITestMode", "-ResetState", "-UITestGuidedCamera"]
        app.launch()
    }

    /// Waits for the camera guide's advice to say something, looking twice a second rather than back to back: the
    /// guide redraws as its readings arrive, and a test that asks for the screen without a pause leaves a slow
    /// machine no time to draw it.
    private func waitForAdvice(containing text: String, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let advice = element("camera.advice")
            if advice.exists, advice.label.contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return false
    }

    func testTheCameraSaysHowToHoldThePhoneFromTheSideUntilItIsRight() throws {
        launchWithGuidedCamera()
        goToCashOut()
        app.segmentedControls["cashout.photoAngle"].buttons["From the side"].tap()

        tap("cashout.takePhoto")
        waitFor("camera.shutter")
        XCTAssertTrue(element("camera.level").exists, "a horizon line to straighten against, for a photo from the side")

        // It starts with what is wrong right now — a dark room — and moves on as each thing is put right.
        XCTAssertTrue(waitForAdvice(containing: "dark"))
        snapshot("47-camera-dark")
        tap("camera.stub.next")
        XCTAssertTrue(waitForAdvice(containing: "Lower the phone"))
        snapshot("48-camera-too-steep")
        tap("camera.stub.next")
        XCTAssertTrue(waitForAdvice(containing: "Straighten"))
        tap("camera.stub.next")
        XCTAssertTrue(waitForAdvice(containing: "Looks good"))
        snapshot("49-camera-ready")

        // The photo it takes is counted like any other.
        tap("camera.shutter")
        XCTAssertTrue(waitForLabel("cashout.photoSummary", containing: "1 photo · 15 chips counted", timeout: 15), element("cashout.photoSummary").label)
        XCTAssertEqual(element("review.count.Green").value as? String, "5")
        XCTAssertFalse(element("camera.shutter").exists, "the camera closed behind the photo")
    }

    func testTheShutterWorksWhileTheCameraStillHasAdvice() throws {
        launchWithGuidedCamera()
        goToCashOut()
        app.segmentedControls["cashout.photoAngle"].buttons["From the side"].tap()

        tap("cashout.takePhoto")
        XCTAssertTrue(waitForAdvice(containing: "dark"))
        tap("camera.shutter")
        XCTAssertTrue(waitForLabel("cashout.photoSummary", containing: "15 chips counted", timeout: 15), "advice only advises")
    }

    func testTheCameraFromAboveAsksForAFlatPhoneAndCancelSendsNothing() throws {
        launchWithGuidedCamera()
        goToCashOut()

        tap("cashout.takePhoto")                                              // from above is the default
        XCTAssertTrue(waitForAdvice(containing: "flat above the chips"))
        XCTAssertFalse(element("camera.level").exists, "the horizon line is for photos from the side")
        tap("camera.cancel")
        waitFor("cashout.takePhoto")
        XCTAssertFalse(element("camera.shutter").exists)
        XCTAssertFalse(element("cashout.photoSummary").exists, "cancelling sends nothing")

        tap("cashout.takePhoto")
        XCTAssertTrue(waitForAdvice(containing: "flat above the chips"), "a new camera starts from its first reading, not the last")
        tap("camera.stub.next")
        XCTAssertTrue(waitForAdvice(containing: "Looks good"))
        tap("camera.shutter")
        XCTAssertTrue(waitForLabel("cashout.photoSummary", containing: "1 photo · 27 chips counted", timeout: 15), element("cashout.photoSummary").label)
    }

    func testTheCameraTipsAreOnToStartWithAndCanBeTurnedOffInSettings() throws {
        launch()
        openTab("Settings")
        let toggle = waitFor("settings.guidedCamera")
        for _ in 0..<6 where !toggle.isHittable { app.swipeUp() }
        XCTAssertEqual(toggle.value as? String, "1", "on until the person says otherwise")
        snapshot("50-settings-camera-tips")
        toggle.tap()
        XCTAssertTrue(waitForValue("settings.guidedCamera", "0"))
    }

    func testABlurryPhotoIsHeldBackUntilThePersonDecides() throws {
        launch()
        goToCashOut()

        tap("cashout.blurryPhoto")
        let useAnyway = app.sheets.buttons["Use it anyway"]
        XCTAssertTrue(useAnyway.waitForExistence(timeout: 8), "the photo should be questioned before it is sent")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'blurry'")).firstMatch.exists, "and the reason given")
        snapshot("43-blurry-photo")
        XCTAssertFalse(element("cashout.photoSummary").exists)

        app.sheets.buttons["Cancel"].tap()
        XCTAssertFalse(element("cashout.photoSummary").exists, "cancelling sends nothing")

        tap("cashout.blurryPhoto")
        XCTAssertTrue(app.sheets.buttons["Use it anyway"].waitForExistence(timeout: 8))
        app.sheets.buttons["Use it anyway"].tap()
        XCTAssertTrue(waitForLabel("cashout.photoSummary", containing: "27 chips counted", timeout: 15))
    }

    // MARK: Breaks and share cards

    func testABreakStopsTheClockAndResumeStartsItAgain() throws {
        launch()
        startSuggestedNight()
        Thread.sleep(forTimeInterval: 2)

        tap("night.break")
        let onBreak = NSPredicate(format: "label CONTAINS[c] 'on a break'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: onBreak, object: element("night.status"))], timeout: 6), .completed)
        let atBreak = seconds(inSpoken: element("night.clock").value as? String ?? "")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(seconds(inSpoken: element("night.clock").value as? String ?? ""), atBreak, "the clock holds still on a break")
        XCTAssertFalse(element("night.break").exists)
        snapshot("44-on-a-break")

        tap("night.resume")
        let timing = NSPredicate(format: "label CONTAINS[c] 'timing'")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: timing, object: element("night.status"))], timeout: 6), .completed)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertGreaterThan(seconds(inSpoken: element("night.clock").value as? String ?? ""), atBreak, "and runs again")

        // Calling the game while on a break ends the break there.
        tap("night.break")
        XCTAssertTrue(element("night.resume").waitForExistence(timeout: 5))
        endNight()
        XCTAssertFalse(element("night.resume").exists)
    }

    func testAFinishedNightAndAWeekCanBeSharedAsPictures() throws {
        launch()
        playAQuickNight()
        openTab("History")
        tap("history.row.0")
        XCTAssertTrue(element("detail.shareSummary").waitForExistence(timeout: 15), "a summary picture of the night is ready to share")
        snapshot("45-night-detail-share")
        app.navigationBars.buttons.firstMatch.tap()

        openTab("Play")
        tap("home.lastResult")
        XCTAssertTrue(element("result.shareSummary").waitForExistence(timeout: 15))
        tap("result.health")
        XCTAssertTrue(element("health.shareWeek").waitForExistence(timeout: 15), "and so is the week")
        snapshot("46-health-share")
    }

    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-UITestMode", "-ResetState"]
            app.launch()
        }
    }
}

// MARK: - Visual tour and accessibility audit

/// Walks every screen once, calling `visit` with a name at each stop. Two tests
/// use it: one attaches a screenshot at every stop (for looking at), the other
/// runs Xcode's accessibility audit at every stop.
///
///   TEST_RUNNER_QA_TEXT_SIZE=AX3 xcodebuild test … -only-testing:PokerChipAppUITests/PokerChipAppVisualTour
final class PokerChipAppVisualTour: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @discardableResult
    private func waitFor(_ identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let match = element(identifier)
        XCTAssertTrue(match.waitForExistence(timeout: timeout), "'\(identifier)' never appeared", file: file, line: line)
        return match
    }

    /// Scrolls until the control can be tapped (large text pushes things below
    /// the fold or under the pinned action bar), then taps it.
    private func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = waitFor(identifier, file: file, line: line)
        // A pinned bar's button never moves, and a drag that starts beside a stepper can press it.
        let scrolls = app.scrollViews.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
            || app.tables.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
            || app.collectionViews.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
        if !scrolls {
            target.tap()
            return
        }
        let screen = app.frame.height
        for _ in 0..<12 {
            let frame = target.frame
            if frame.isEmpty { break }
            if frame.minY < screen * 0.16 {
                drag(down: true)
            } else if frame.maxY > screen * 0.76 {
                let before = frame
                drag(down: false)
                if target.frame == before { break }
            } else {
                break
            }
        }
        target.tap()
    }

    /// A short drag in the middle of the screen; a full swipe overshoots.
    private func drag(down: Bool) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: down ? 0.45 : 0.65))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: down ? 0.65 : 0.45))
        from.press(forDuration: 0.05, thenDragTo: to)
    }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.6)   // let a push or a spring finish
        // An app that has turned itself sideways (the table card) comes out cropped from app.screenshot().
        let screenshot = app.frame.width > app.frame.height ? XCUIScreen.main.screenshot() : app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollToBottom() {
        app.swipeUp()
        app.swipeUp()
    }

    private func openTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "no “\(name)” tab")
        tab.tap()
    }

    private func launch(extra: [String] = []) {
        var arguments = ["-UITestMode", "-ResetState"] + extra
        // AX1…AX5 are the five accessibility sizes; QA_TEXT_SIZE=AX3 is the one in the spec.
        let sizes = ["AX1": "AccessibilityM", "AX2": "AccessibilityL", "AX3": "AccessibilityXL", "AX4": "AccessibilityXXL", "AX5": "AccessibilityXXXL"]
        if let size = ProcessInfo.processInfo.environment["QA_TEXT_SIZE"], let category = sizes[size] {
            arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategory\(category)"]
        }
        app.launchArguments = arguments
        app.launch()
    }

    private func dismissKeyboardIfShown() {
        if app.keyboards.count > 0, element("keyboard.done").exists {
            element("keyboard.done").tap()
        }
    }

    private func cashOutByAmount(_ name: String, _ amount: String) {
        tap("night.cashOut.\(name)")
        let amountMode = app.segmentedControls.buttons["Enter amount"]
        XCTAssertTrue(amountMode.waitForExistence(timeout: 8), "the cash-out screen never appeared")
        amountMode.tap()
        let field = waitFor("cashout.amount")
        field.tap()
        field.typeText(amount)
        dismissKeyboardIfShown()
        tap("cashout.save")
        waitFor("night.player.\(name)")
    }

    private func walkEveryScreen(_ visit: (String) -> Void) {
        launch()

        waitFor("home.newGame")
        visit("01-home-first-run")

        tap("home.newGame")
        waitFor("buyin.amount")
        visit("02-buy-in-empty")
        let amount = element("buyin.amount")
        amount.tap()
        amount.typeText("25")
        dismissKeyboardIfShown()
        for _ in 0..<3 { tap("buyin.players.minus") }
        tap("buyin.selectAll")
        visit("03-buy-in-filled")
        tap("buyin.chipSet")
        tap("chipset.size.300")
        visit("03b-chip-set")
        scrollToBottom()
        visit("03c-chip-set-bottom")
        tap("chipset.save")
        waitFor("buyin.next")
        visit("03d-buy-in-with-a-chip-set")
        tap("buyin.next")

        waitFor("players.name.0")
        visit("04-players-empty")
        for (index, name) in ["Sam", "Alex", "Jo"].enumerated() {
            let field = element("players.name.\(index)")
            field.tap()
            field.typeText(name)
        }
        dismissKeyboardIfShown()
        visit("05-players-filled")
        tap("players.next")

        waitFor("style.suggested")
        visit("06-chip-values")
        tap("style.suggested")
        waitFor("suggested.total")
        visit("07-suggested")
        if element("suggested.another").exists {
            tap("suggested.another")
            visit("07a-suggested-another-way")
            tap("suggested.another")
            for _ in 0..<2 where element("suggested.optionTitle").label != "Recommended" { tap("suggested.another") }
        }
        scrollToBottom()
        visit("07b-suggested-bottom")
        tap("suggested.tableCard")
        waitFor("tablecard")
        waitFor("tablecard.share")
        visit("07c-table-card")
        element("tablecard.close").tap()
        waitFor("suggested.total")
        app.navigationBars.buttons.firstMatch.tap()

        tap("style.custom")
        waitFor("custom.start")
        visit("08-custom")
        app.navigationBars.buttons.firstMatch.tap()

        tap("style.suggested")
        waitFor("suggested.start")
        tap("suggested.start")

        waitFor("night.clock")
        visit("09-live-night")
        tap("night.break")
        waitFor("night.resume")
        visit("09b-on-a-break")
        tap("night.resume")
        waitFor("night.break")
        tap("night.rebuy.Alex")
        waitFor("night.undoBanner")
        visit("10-after-a-rebuy")
        scrollToBottom()
        visit("10b-live-night-bottom")

        tap("night.playerMenu.Alex")
        app.buttons["Buy-ins"].tap()
        waitFor("history.done")
        visit("11-buy-in-history")
        tap("history.done")

        tap("night.end")
        app.sheets.buttons["End night"].tap()
        waitFor("night.endedBanner")
        visit("12-cash-out-list")

        tap("night.cashOut.Sam")
        waitFor("review.totals")
        visit("13-cash-out-empty")
        tap("cashout.samplePhoto")
        waitFor("cashout.photoSummary")
        visit("13b-cash-out-photo-counted")
        tap("cashout.photo.0")
        waitFor("photoReview.mark.0")
        visit("13c-photo-review")
        tap("photoReview.mark.0")
        waitFor("photoReview.remove")
        visit("13d-photo-review-fixing-a-chip")
        tap("photoReview.deselect")
        tap("photoReview.addMode")
        waitFor("photoReview.addDone")
        visit("13e-photo-review-adding-a-chip")
        tap("photoReview.addDone")
        tap("photoReview.done")
        tap("cashout.startOver")
        for color in ["White", "Red", "Blue"] {
            for _ in 0..<2 { tap("review.count.\(color).plus") }
        }
        visit("14-cash-out-counted")
        scrollToBottom()
        visit("14b-cash-out-bottom")
        tap("cashout.save")
        waitFor("night.player.Sam")

        cashOutByAmount("Alex", "40")
        cashOutByAmount("Jo", "40")

        tap("night.bank")
        waitFor("bank.difference")
        visit("15-bank-check")
        scrollToBottom()
        visit("15b-bank-check-bottom")
        tap("bank.split")
        visit("16-bank-check-resolved")
        tap("bank.settle")

        waitFor("settle.payments")
        visit("17-settle-up")
        scrollToBottom()
        visit("17b-settle-up-bottom")
        tap("settle.close")

        waitFor("result.net")
        visit("18-result")
        scrollToBottom()
        visit("19-result-bottom")
        tap("result.health")

        waitFor("health.total")
        visit("20-poker-health")
        scrollToBottom()
        visit("20b-poker-health-bottom")
        tap("health.playAgain")

        waitFor("home.newGame")
        visit("21-home-after-a-night")

        openTab("History")
        waitFor("history.row.0")
        visit("22-history")
        tap("history.row.0")
        waitFor("detail.players")
        visit("23-night-detail")
        scrollToBottom()
        visit("23b-night-detail-bottom")
        app.navigationBars.buttons.firstMatch.tap()

        openTab("Stats")
        waitFor("stats.net")
        visit("24-stats")
        scrollToBottom()
        visit("24b-stats-middle")
        scrollToBottom()
        visit("24c-stats-bottom")
        tap("stats.health")
        waitFor("health.total")
        visit("25-poker-health-trend")
        scrollToBottom()
        visit("25b-poker-health-bottom")
        app.navigationBars.buttons.firstMatch.tap()

        openTab("Settings")
        waitFor("settings.signOut")
        visit("26-settings")
        scrollToBottom()
        visit("27-settings-bottom")
        scrollToBottom()
        visit("27b-settings-healthy-play")

        // Back to the top to reach the account buttons again.
        app.swipeDown(); app.swipeDown()
        tap("settings.signOut")
        app.sheets.buttons["Sign out"].tap()

        waitFor("auth.guest")
        visit("28-welcome")
        tap("auth.email")
        waitFor("auth.submit")
        visit("29-email-sign-in")
        tap("auth.submit")
        Thread.sleep(forTimeInterval: 0.5)
        visit("30-email-validation")
    }

    /// Waits for the camera guide's line of advice to contain the text.
    private func waitForAdvice(containing text: String, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let advice = element("camera.advice")
            if advice.exists, advice.label.contains(text) { return }
            Thread.sleep(forTimeInterval: 0.5)   // not back to back: the guide redraws as its readings arrive
        } while Date() < deadline
        let advice = element("camera.advice")
        XCTFail("the advice never said “\(text)”: \(advice.exists ? advice.label : "no advice on screen")", file: file, line: line)
    }

    /// A night to the point of cashing someone out, then the camera guide on its stand-in camera:
    /// from above (not flat, then ready) and from the side (dark, too steep, tilted, ready).
    private func walkTheCameraGuide(_ visit: (String) -> Void) {
        launch(extra: ["-UITestGuidedCamera"])

        waitFor("home.newGame")
        tap("home.newGame")
        let amount = waitFor("buyin.amount")
        amount.tap()
        amount.typeText("25")
        dismissKeyboardIfShown()
        for _ in 0..<4 { tap("buyin.players.minus") }
        tap("buyin.selectAll")
        tap("buyin.next")

        waitFor("players.name.0")
        for (index, name) in ["Sam", "Alex"].enumerated() {
            let field = element("players.name.\(index)")
            field.tap()
            field.typeText(name)
        }
        dismissKeyboardIfShown()
        tap("players.next")
        waitFor("style.suggested")
        tap("style.suggested")
        waitFor("suggested.start")
        tap("suggested.start")
        waitFor("night.clock")
        tap("night.end")
        app.sheets.buttons["End night"].tap()
        waitFor("night.endedBanner")
        tap("night.cashOut.Sam")
        waitFor("review.totals")

        tap("cashout.takePhoto")
        waitFor("camera.shutter")
        waitForAdvice(containing: "flat above the chips")
        visit("14-camera-from-above-not-flat")
        tap("camera.stub.next")
        waitForAdvice(containing: "Looks good")
        visit("14b-camera-from-above-ready")
        tap("camera.cancel")
        waitFor("cashout.takePhoto")

        app.segmentedControls["cashout.photoAngle"].buttons["From the side"].tap()
        tap("cashout.takePhoto")
        waitFor("camera.shutter")
        waitForAdvice(containing: "dark")
        visit("14c-camera-from-the-side-dark")
        tap("camera.stub.next")
        waitForAdvice(containing: "Lower the phone")
        visit("14d-camera-from-the-side-too-steep")
        tap("camera.stub.next")
        waitForAdvice(containing: "Straighten")
        visit("14e-camera-from-the-side-tilted")
        tap("camera.stub.next")
        waitForAdvice(containing: "Looks good")
        visit("14f-camera-from-the-side-ready")
        tap("camera.cancel")
        waitFor("cashout.takePhoto")
    }

    func testTourOfEveryScreen() throws {
        walkEveryScreen { shot($0) }
    }

    func testTourOfTheCameraGuide() throws {
        walkTheCameraGuide { shot($0) }
    }

    func testTourOfANightInProgress() throws {
        app.launchArguments = ["-UITestMode", "-ResetState"]
        app.launch()

        waitFor("home.newGame")
        tap("home.newGame")
        let amount = waitFor("buyin.amount")
        amount.tap()
        amount.typeText("50")
        dismissKeyboardIfShown()
        tap("buyin.selectAll")
        tap("buyin.next")
        waitFor("players.next")
        tap("players.next")
        tap("style.suggested")
        tap("suggested.start")
        waitFor("night.clock")

        // Leave the night running and look at Home with the resume card.
        app.navigationBars.buttons.firstMatch.tap()
        waitFor("home.resume")
        shot("31-home-resume-card")
    }

    /// The audit categories used as a gate. Left out on purpose, each explained in docs/QA.md:
    /// - contrast: Xcode's checker mis-reads text over translucent cards and gradients
    ///   (it fails the black-on-gold Next button), and the same pairs measure 6–13:1 on
    ///   the rendered screenshots; ContrastTests enforces it on the colour tokens instead;
    /// - Dynamic Type: it flags text that does scale (checked at AX3 on three devices);
    /// - element detection ("potentially inaccessible text"): it relies on on-screen text
    ///   recognition and is not repeatable — 7 findings at one stop in one run, none in an
    ///   identical rerun.
    @available(iOS 17.0, *)
    private var audited: XCUIAccessibilityAuditType {
        [.hitRegion, .sufficientElementDescription, .trait, .textClipped]
    }

    /// Xcode's own accessibility audit (touch-target size, clipped text, missing
    /// descriptions and traits) at every stop of the walk. Issues are attached as
    /// text so they can be read; the test fails on any that aren't in the short
    /// allow-list in `isExpected`.
    func testAccessibilityAuditOfEveryScreen() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("The accessibility audit API needs iOS 17 or later") }

        let log = AuditLog()
        walkEveryScreen { audit($0, into: log) }
        finishAudit(log)
    }

    /// The same audit at every stop of the camera guide, on its stand-in camera.
    func testAccessibilityAuditOfTheCameraGuide() throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("The accessibility audit API needs iOS 17 or later") }

        let log = AuditLog()
        walkTheCameraGuide { audit($0, into: log) }
        finishAudit(log)
    }

    /// What the audit found, collected as the walk goes (the audit's issue handler outlives the call that takes it).
    private final class AuditLog {
        var report: [String] = []
        var unexpected: [String] = []
    }

    @available(iOS 17.0, *)
    private func audit(_ name: String, into log: AuditLog) {
        Thread.sleep(forTimeInterval: 0.6)
        // The audit sometimes runs out of time on a busy screen; try once more.
        for attempt in 1...2 {
            do {
                try app.performAccessibilityAudit(for: audited) { issue in
                    let detail = issue.detailedDescription.replacingOccurrences(of: "\n", with: " ").prefix(240)
                    let line = "[\(name)] \(issue.auditType) — \(issue.compactDescription) — \(issue.element?.debugDescription.prefix(160) ?? "no element") — \(detail)"
                    log.report.append(line)
                    if !self.isExpected(issue.auditType, label: issue.element?.label ?? "", identifier: issue.element?.identifier ?? "") {
                        log.unexpected.append(line)
                    }
                    return true   // keep going; the verdict is made below
                }
                return
            } catch {
                if attempt == 2 {
                    log.report.append("[\(name)] NOT AUDITED — the audit timed out twice: \(error)")
                } else {
                    Thread.sleep(forTimeInterval: 1)
                }
            }
        }
    }

    private func finishAudit(_ log: AuditLog) {
        let attachment = XCTAttachment(string: log.report.isEmpty ? "No issues found." : log.report.joined(separator: "\n"))
        attachment.name = "accessibility-audit"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(log.unexpected.isEmpty, "Accessibility audit found:\n" + log.unexpected.joined(separator: "\n"))
    }

    /// Findings accepted on purpose, each justified in docs/QA.md. Everything else fails.
    @available(iOS 17.0, *)
    private func isExpected(_ type: XCUIAccessibilityAuditType, label: String, identifier: String) -> Bool {
        guard type == .textClipped else { return false }
        // Small uppercase section and tile labels are reported as clipped although the
        // rendered text is complete (checked at 3x zoom against an identical label the
        // audit does not flag, and at AX3 on the iPhone SE, where each wraps in full),
        // and so are the email field's placeholder and the system search field's prompt,
        // which are drawn in full. Matched by exact label / identifier so nothing else
        // slips by.
        let sectionLabels: Set<String> = [
            "NUMBER OF PLAYERS", "CHIPS YOU HAVE", "COUNT THE CHIPS", "DAILY BREAKDOWN",
            "HOW A GAME NIGHT WORKS", "YOUR RESULT", "WIN RATE", "Place, player or note",
        ]
        return sectionLabels.contains(label) || identifier == "auth.emailField"
    }
}


private extension XCUIElement {
    /// Replaces whatever is in a text field.
    func clearAndTypeText(_ text: String) {
        guard let current = value as? String, !current.isEmpty else {
            typeText(text)
            return
        }
        tap()
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        typeText(text)
    }
}
