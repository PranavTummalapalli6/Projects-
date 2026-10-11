//
//  ViewModelTests.swift
//  PokerChipAppTests
//
//  The logic behind the screens: cashing a player out (counting, typing an
//  amount, a photo that helps or fails), navigation, the suggested chips, and
//  sign-in form validation.
//

import XCTest
@testable import PokerChipApp

private let t0 = Date(timeIntervalSince1970: 1_786_042_800)

private func twoPlayerNight(buyIn: Int = 2_500) -> GameNight {
    GameNight.start(
        now: t0, buyInMinor: buyIn, playerNames: ["Sam", "Alex"],
        colors: ["White", "Red"], denominationsMinor: ["White": 25, "Red": 100],
        startingCounts: ["White": 40, "Red": 15]
    )
}

// MARK: - Cashing a player out

@MainActor
final class CashOutViewModelTests: XCTestCase {
    private func viewModel(
        _ night: GameNight,
        player: Int = 0,
        client: ChipVisionAPIClient = Script([]).client()
    ) -> CashOutViewModel {
        CashOutViewModel(target: CashOutTarget(nightID: night.id, playerID: night.players[player].id), night: night, client: client)
    }

    func testItStartsInChipCountingWithNothingCounted() {
        let model = viewModel(twoPlayerNight())
        XCTAssertEqual(model.mode, .chips)
        XCTAssertEqual(model.colors, ["White", "Red"], "only this night's colours, in table order")
        XCTAssertEqual(model.counts, ["White": 0, "Red": 0])
        XCTAssertEqual(model.cashOutMinor, 0)
        XCTAssertEqual(model.netMinor, -2_500)
        XCTAssertFalse(model.isEditing)
        XCTAssertFalse(model.isMissing)
    }

    func testCountedChipsAreWorthExactCents() {
        let model = viewModel(twoPlayerNight())
        model.counts = ["White": 60, "Red": 17]            // 60 × $0.25 + 17 × $1.00

        XCTAssertEqual(model.subtotalMinor("White"), 1_500)
        XCTAssertEqual(model.subtotalMinor("Red"), 1_700)
        XCTAssertEqual(model.chipsMinor, 3_200)
        XCTAssertEqual(model.cashOutMinor, 3_200)
        XCTAssertEqual(model.netMinor, 700)
    }

    func testTypingAnAmountIsStrictAboutWhatItAccepts() {
        let model = viewModel(twoPlayerNight())
        model.mode = .amount

        for (text, expected) in [("", nil), ("abc", nil), ("-5", nil), ("1000000.01", nil), ("0", 0), ("12.50", 1_250), ("25", 2_500)] as [(String, Int?)] {
            model.amountText = text
            XCTAssertEqual(model.cashOutMinor, expected, "“\(text)”")
        }
        model.amountText = "40"
        XCTAssertEqual(model.netMinor, 1_500)
    }

    func testFixingACashOutStartsFromTheAmountAlreadyRecorded() {
        var night = twoPlayerNight()
        night.cashOut(night.players[0].id, amountMinor: 4_250, at: t0)
        let model = viewModel(night)

        XCTAssertTrue(model.isEditing)
        XCTAssertEqual(model.mode, .amount)
        XCTAssertEqual(model.cashOutMinor, 4_250)
    }

    func testTheChipsEachPlayerWasDealtAreShownOnlyWhenEveryBuyInWasTheStandardOne() {
        var night = twoPlayerNight()
        night.rebuy(night.players[0].id)                                 // one standard rebuy: twice the chips
        night.rebuy(night.players[1].id, amountMinor: 1_000)             // a different amount: unknown
        XCTAssertEqual(viewModel(night, player: 0).dealtChips, ["White": 80, "Red": 30])
        XCTAssertNil(viewModel(night, player: 1).dealtChips)
        XCTAssertEqual(viewModel(night, player: 0).totalInMinor, 5_000)
    }

    func testSavingRecordsTheCashOutOnTheNight() async {
        let store = NightStore(repository: MemoryNightRepository())
        await store.load()
        let night = store.start(twoPlayerNight())
        let model = viewModel(night)
        model.counts = ["White": 40, "Red": 20]                          // $10.00 + $20.00

        XCTAssertTrue(model.save(into: store, now: t0))

        XCTAssertEqual(store.night(night.id)?.players[0].cashOutMinor, 3_000)
        XCTAssertEqual(store.night(night.id)?.players[1].cashOutMinor, nil, "only this player")
    }

    func testAnInvalidAmountIsNotSaved() async {
        let store = NightStore(repository: MemoryNightRepository())
        await store.load()
        let night = store.start(twoPlayerNight())
        let model = viewModel(night)
        model.mode = .amount
        model.amountText = "lots"

        XCTAssertFalse(model.save(into: store))
        XCTAssertNil(store.night(night.id)?.players[0].cashOutMinor)
    }

    func testAPlayerWhoIsGoneOrANightThatIsGoneShowsAsMissing() {
        let night = twoPlayerNight()
        XCTAssertTrue(CashOutViewModel(target: CashOutTarget(nightID: night.id, playerID: UUID()), night: night).isMissing)
        XCTAssertTrue(CashOutViewModel(target: CashOutTarget(nightID: night.id, playerID: night.players[0].id), night: nil).isMissing)
    }

    // MARK: A photo that helps, or doesn't

    private func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
    }

    func testAPhotoFillsInTheCountsButLeavesThemEditable() async {
        let script = Script([.respond(status: 200, body: #"{"counts": {"White": 33, "Red": 9}, "confidence": "medium", "photoUrl": ""}"#)])
        let night = twoPlayerNight()
        let model = viewModel(night, client: script.client())

        await model.submitPhoto(photo()).value

        XCTAssertEqual(model.counts, ["White": 33, "Red": 9])
        XCTAssertEqual(model.photoNotice, .counted(confidence: "medium", ignored: 0))
        XCTAssertFalse(model.isUploading)
        XCTAssertEqual(script.requests.first?.url?.path.hasPrefix("/v1/sessions/\(night.id.uuidString)-"), true)

        model.counts["White"] = 35                                        // the person corrects it
        XCTAssertEqual(model.subtotalMinor("White"), 875)
    }

    func testAPhotoThatCannotBeCountedSaysWhyAndLeavesTheCountsAlone() async {
        let model = viewModel(twoPlayerNight(), client: Script([.fail(URLError(.notConnectedToInternet))]).client())
        model.counts["Red"] = 4

        await model.submitPhoto(photo()).value

        guard case .failed(let message)? = model.photoNotice else { return XCTFail("expected a failure notice, got \(String(describing: model.photoNotice))") }
        XCTAssertTrue(message.contains("Count by hand"))
        XCTAssertEqual(model.counts["Red"], 4, "nothing already entered is thrown away")
        XCTAssertFalse(model.isUploading)
    }

    func testColoursNotInThisNightAreIgnoredWhenAPhotoIsRead() async {
        let script = Script([.respond(status: 200, body: #"{"counts": {"White": 5, "Black": 99}, "confidence": "high", "photoUrl": ""}"#)])
        let model = viewModel(twoPlayerNight(), client: script.client())
        await model.submitPhoto(photo()).value
        XCTAssertEqual(model.counts, ["White": 5, "Red": 0])
        XCTAssertEqual(model.photoNotice, .counted(confidence: "high", ignored: 99), "and the person is told some were left out")
    }
}

// MARK: - Navigation

@MainActor
final class NavigationCoordinatorTests: XCTestCase {
    func testOpeningANightReplacesTheSetupScreensSoBackLandsOnHome() {
        let coordinator = NavigationCoordinator()
        let setup = GameSetup(buyIn: 25, players: 6, availableColors: ["White"])
        coordinator.path = [.buyIn(nil), .players(setup), .chipStyle(setup), .suggested(setup)]

        let id = UUID()
        coordinator.open(night: id)

        XCTAssertEqual(coordinator.path, [.night(id)], "Back from the night lands on Home, not on a second Start button")
    }

    func testPushPopAndPopToRootEvenOnAnEmptyStack() {
        let coordinator = NavigationCoordinator()
        coordinator.pop()   // must not crash
        XCTAssertTrue(coordinator.path.isEmpty)

        let id = UUID()
        coordinator.open(night: id)
        coordinator.push(.pokerHealth)
        coordinator.pop()
        XCTAssertEqual(coordinator.path, [.night(id)])

        coordinator.popToRoot()
        XCTAssertTrue(coordinator.path.isEmpty)
    }

    func testEveryRouteCanBeHashedSoItCanLiveInANavigationPath() {
        let id = UUID()
        let routes: [AppRoute] = [
            .night(id), .cashOut(CashOutTarget(nightID: id, playerID: id)), .bankCheck(id), .settleUp(id), .result(id),
            .players(GameSetup(buyIn: 25, players: 2, availableColors: ["White"], playerNames: ["A", "B"])),
        ]
        XCTAssertEqual(Set(routes).count, routes.count)
    }
}

// MARK: - Suggested chips

@MainActor
final class SuggestedViewModelTests: XCTestCase {
    func testAFullSetSplitsAMiddlingBuyInExactly() async {
        let setup = GameSetup(buyIn: 25, players: 6, availableColors: Set(allChipColors))
        let outcome = await SuggestedViewModel.outcome(for: setup)

        guard case .ready(let options) = outcome, let suggestion = options.first else { return XCTFail("expected a suggestion, got \(outcome)") }
        XCTAssertEqual(suggestion.kind, .recommended)
        XCTAssertEqual(suggestion.rows.map(\.color), allChipColors)
        XCTAssertEqual(suggestion.totalCents, 2_500)
        XCTAssertEqual(suggestion.valuesMinor.count, 5)
        XCTAssertEqual(suggestion.counts.values.reduce(0, +), suggestion.totalChips)
        XCTAssertEqual(suggestion.rows.map(\.count), suggestion.rows.map(\.count).sorted(by: >), "fewer chips of higher value")
    }

    func testATinyBuyInOverFiveColoursIsReportedAsTooSmallWithTheNextOneThatWorks() async {
        let setup = GameSetup(buyIn: 1, players: 6, availableColors: Set(allChipColors))
        let outcome = await SuggestedViewModel.outcome(for: setup)
        XCTAssertEqual(outcome, .tooSmall(nextWorkingCents: 315), "five colours need $3.15 at the least")
    }

    func testAskingTwiceGivesTheSameAnswer() async {
        let setup = GameSetup(buyIn: 40, players: 8, availableColors: ["White", "Red", "Blue"])
        let first = await SuggestedViewModel.outcome(for: setup)
        let second = await SuggestedViewModel.outcome(for: setup)
        XCTAssertEqual(first, second)
    }

    func testTheViewModelReportsLoadedAfterLoading() async {
        let model = SuggestedViewModel()
        await model.load(for: GameSetup(buyIn: 20, players: 4, availableColors: ["White", "Red"]))
        guard case .loaded(.ready) = model.state else { return XCTFail("expected loaded, got \(model.state)") }
        XCTAssertNotNil(model.current)
    }

    // MARK: Other ways to deal it

    func testAnotherOptionCyclesThroughTheWaysToDealTheSameBuyIn() async throws {
        let model = SuggestedViewModel()
        var found = false
        for buyIn in stride(from: 10.0, through: 200.0, by: 5.0) {
            await model.load(for: GameSetup(buyIn: buyIn, players: 6, availableColors: Set(allChipColors)))
            guard model.optionCount > 1 else { continue }
            found = true
            let first = try XCTUnwrap(model.current)
            XCTAssertEqual(first.kind, .recommended)
            XCTAssertEqual(model.selected, 0)

            model.nextOption()
            let second = try XCTUnwrap(model.current)
            XCTAssertNotEqual(second, first)
            XCTAssertEqual(second.totalCents, first.totalCents, "every option deals the same buy-in")

            for _ in 1..<model.optionCount { model.nextOption() }
            XCTAssertEqual(model.current, first, "after the last option it comes back to the first")
            break
        }
        XCTAssertTrue(found, "some buy-in has more than one way to deal it")
    }

    func testWithOnlyOneOptionThereIsNothingToCycleTo() async throws {
        let model = SuggestedViewModel()
        await model.load(for: GameSetup(buyIn: 25, players: 6, availableColors: ["White"]))
        XCTAssertEqual(model.optionCount, 1)
        let before = try XCTUnwrap(model.current)
        model.nextOption()
        XCTAssertEqual(model.current, before)
        XCTAssertEqual(model.selected, 0)
    }

    func testLoadingAgainStartsOnTheRecommendedStack() async {
        let model = SuggestedViewModel()
        let setup = GameSetup(buyIn: 40, players: 6, availableColors: Set(allChipColors))
        await model.load(for: setup)
        model.nextOption()
        await model.load(for: setup)
        XCTAssertEqual(model.selected, 0)
    }

    // MARK: A set that is too small

    func testASetTooSmallForTheTableIsReportedWithThingsThatWouldWork() async {
        let small = ChipInventory.preset(.hundred, colors: allChipColors)
        let setup = GameSetup(buyIn: 25, players: 8, availableColors: Set(allChipColors), inventory: small)
        let outcome = await SuggestedViewModel.outcome(for: setup)

        guard case .setTooSmall(let alternatives) = outcome else { return XCTFail("expected setTooSmall, got \(outcome)") }
        XCTAssertFalse(alternatives.isEmpty)
        for alternative in alternatives {
            let changed = setup.applying(alternative)
            let after = await SuggestedViewModel.outcome(for: changed)
            guard case .ready = after else { XCTFail("\(alternative) should leave a table that works, got \(after)"); continue }
        }
    }

    func testPrintedValuesThatCantMakeTheAmountAreReportedWithNearbyOnes() async {
        let printed = ChipInventory(owned: ["White": 200, "Red": 100], printedValues: ["White": 100, "Red": 500])
        let setup = GameSetup(buyIn: 2.50, players: 4, availableColors: ["White", "Red"], inventory: printed)
        let outcome = await SuggestedViewModel.outcome(for: setup)
        guard case .noExactSplit(let nearby) = outcome else { return XCTFail("expected noExactSplit, got \(outcome)") }
        XCTAssertFalse(nearby.isEmpty)
    }

    func testValuesFixedOutOfOrderAreReportedAsAConflict() async {
        let setup = GameSetup(buyIn: 25, players: 6, availableColors: ["White", "Red", "Blue"], lockedValues: ["White": 500, "Red": 100])
        let outcome = await SuggestedViewModel.outcome(for: setup)
        XCTAssertEqual(outcome, .valuesConflict)
    }

    func testNoColoursIsReportedAsSuch() async {
        let outcome = await SuggestedViewModel.outcome(for: GameSetup(buyIn: 25, players: 6, availableColors: []))
        XCTAssertEqual(outcome, .noColors)
    }

    // MARK: Fixing a value

    func testAFixedValueStaysWhileTheRestIsWorkedOutAroundIt() async throws {
        var setup = GameSetup(buyIn: 25, players: 6, availableColors: Set(allChipColors))
        let before = await SuggestedViewModel.outcome(for: setup)
        guard case .ready(let beforeOptions) = before, let original = beforeOptions.first else { return XCTFail("expected a suggestion") }

        let target = try XCTUnwrap(original.rows.first(where: { $0.color == "Blue" }))
        let other = [10, 25, 50, 100].first(where: { $0 != target.valueCents }) ?? 50
        setup.lockedValues["Blue"] = other
        let after = await SuggestedViewModel.outcome(for: setup)
        guard case .ready(let options) = after, let fixed = options.first else {
            // A value can legitimately make the rest impossible; then it is a conflict, not a wrong stack.
            XCTAssertEqual(after, .valuesConflict)
            return
        }
        XCTAssertEqual(fixed.rows.first(where: { $0.color == "Blue" })?.valueCents, other)
        XCTAssertEqual(fixed.totalCents, 2_500)
    }

    func testWhatTheAnswerDependsOnIsWhatTheCacheKeyDependsOn() {
        let base = GameSetup(buyIn: 25, players: 6, availableColors: Set(allChipColors))
        var keys: Set<String> = [SuggestedViewModel.cacheKey(for: base)]

        var other = base; other.buyIn = 30; keys.insert(SuggestedViewModel.cacheKey(for: other))
        other = base; other.players = 7; keys.insert(SuggestedViewModel.cacheKey(for: other))
        other = base; other.colors = ["White", "Red"]; keys.insert(SuggestedViewModel.cacheKey(for: other))
        other = base; other.inventory = ChipInventory.preset(.fiveHundred, colors: allChipColors); keys.insert(SuggestedViewModel.cacheKey(for: other))
        other = base; other.inventory = ChipInventory.preset(.threeHundred, colors: allChipColors); keys.insert(SuggestedViewModel.cacheKey(for: other))
        other = base; other.lockedValues = ["Blue": 50]; keys.insert(SuggestedViewModel.cacheKey(for: other))
        other = base; other.lockedValues = ["Blue": 100]; keys.insert(SuggestedViewModel.cacheKey(for: other))
        XCTAssertEqual(keys.count, 8, "each of these gets its own answer")

        // Names and place don't change the chips.
        other = base; other.playerNames = ["Ann", "Bo"]; other.location = "Kitchen"
        XCTAssertEqual(SuggestedViewModel.cacheKey(for: other), SuggestedViewModel.cacheKey(for: base))
    }
}

final class AlternativeApplicationTests: XCTestCase {
    private let base = GameSetup(buyIn: 25, players: 6, availableColors: Set(allChipColors), playerNames: ["A", "B", "C", "D", "E", "F"], location: "Den")

    func testFewerPlayersDropsTheLastNamesAndKeepsTheRest() {
        let changed = base.applying(ChipAlternative(kind: .fewerPlayers(4)))
        XCTAssertEqual(changed.players, 4)
        XCTAssertEqual(changed.playerNames, ["A", "B", "C", "D"])
        XCTAssertEqual(changed.buyIn, 25)
        XCTAssertEqual(changed.location, "Den")
    }

    func testALowerBuyInChangesOnlyTheBuyIn() {
        let changed = base.applying(ChipAlternative(kind: .lowerBuyIn(cents: 2_000)))
        XCTAssertEqual(changed.buyIn, 20)
        XCTAssertEqual(changed.players, 6)
        XCTAssertEqual(changed.playerNames.count, 6)
    }

    func testLeavingAColourOutAlsoForgetsAValueFixedOnIt() {
        var setup = base
        setup.lockedValues = ["Black": 1_000, "Red": 25]
        let changed = setup.applying(ChipAlternative(kind: .dropColor("Black")))
        XCTAssertEqual(changed.colors, ["White", "Red", "Blue", "Green"])
        XCTAssertEqual(changed.lockedValues, ["Red": 25])
    }
}

// MARK: - Sign-in

@MainActor
final class SignInFormTests: XCTestCase {
    func testNothingIsFlaggedBeforeSomeoneTriesToContinue() {
        let model = SignInEmailViewModel(isLinking: false)
        XCTAssertNil(model.emailProblem())
        XCTAssertNil(model.passwordProblem(for: .signIn))
    }

    func testABadEmailIsExplainedAndNothingIsSent() {
        let model = SignInEmailViewModel(isLinking: false)
        model.email = "not-an-email"
        model.password = "secret1"

        model.submit(mode: .signIn, auth: AuthViewModel(), onLinked: {})

        XCTAssertEqual(model.emailProblem(), "That doesn't look like an email address.")
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.errorMessage)
    }

    func testAMissingPasswordIsExplained() {
        let model = SignInEmailViewModel(isLinking: false)
        model.email = "pat@example.com"

        model.submit(mode: .signIn, auth: AuthViewModel(), onLinked: {})

        XCTAssertNil(model.emailProblem())
        XCTAssertEqual(model.passwordProblem(for: .signIn), "Enter your password.")
        XCTAssertFalse(model.isWorking)
    }

    func testANewAccountNeedsASixCharacterPassword() {
        let model = SignInEmailViewModel(isLinking: false)
        model.email = "pat@example.com"
        model.password = "12345"

        model.submit(mode: .signUp, auth: AuthViewModel(), onLinked: {})

        XCTAssertEqual(model.passwordProblem(for: .signUp), "Use at least 6 characters.")
        XCTAssertNil(model.passwordProblem(for: .signIn), "signing in doesn't second-guess an existing password")
        XCTAssertFalse(model.isWorking)
    }

    func testResettingAPasswordNeedsAnEmailFirst() {
        let model = SignInEmailViewModel(isLinking: false)
        model.email = ""

        model.resetPassword()

        XCTAssertEqual(model.emailProblem(), "Enter your email address.")
        XCTAssertFalse(model.isWorking)
        XCTAssertNil(model.infoMessage)
    }

    func testEmailsWithStrayWhitespaceAreAccepted() {
        let model = SignInEmailViewModel(isLinking: false)
        model.email = "  pat@example.com \n"
        XCTAssertEqual(model.trimmedEmail, "pat@example.com")
    }
}

final class AuthErrorMessageTests: XCTestCase {
    private func message(_ code: Int) -> String {
        AuthErrorMessage.message(for: NSError(domain: "FIRAuthErrorDomain", code: code))
    }

    func testWrongPasswordAndUnknownAccountSayTheSameThing() {
        // So the sign-in form can't be used to find out who has an account.
        XCTAssertEqual(message(17009), message(17011))
        XCTAssertEqual(message(17009), message(17004))
        XCTAssertTrue(message(17009).contains("don't match"))
    }

    func testCommonFailuresHaveSpecificAdvice() {
        XCTAssertTrue(message(17007).contains("already exists"))
        XCTAssertTrue(message(17008).contains("valid email"))
        XCTAssertTrue(message(17010).contains("Too many attempts"))
        XCTAssertTrue(message(17020).contains("offline"))
        XCTAssertTrue(message(17026).contains("6 characters"))
        XCTAssertTrue(message(17006).contains("isn't turned on"), "guest mode before the Anonymous provider is enabled")
    }

    func testServiceErrorsReadAsTheirOwnWords() {
        XCTAssertEqual(AuthErrorMessage.message(for: ChipVisionAPIError.offline), "You're offline.")
        XCTAssertTrue(AuthErrorMessage.message(for: URLError(.notConnectedToInternet)).contains("offline"))
    }
}

// MARK: - Small rules

final class SplashPolicyTests: XCTestCase {
    func testTheSplashShowsOncePerAppVersion() {
        let suite = "tests.splash.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return XCTFail("no defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(SplashPolicy.shouldShow(defaults: defaults, version: "1.0 (1)"))
        SplashPolicy.markShown(defaults: defaults, version: "1.0 (1)")
        XCTAssertFalse(SplashPolicy.shouldShow(defaults: defaults, version: "1.0 (1)"))
        XCTAssertTrue(SplashPolicy.shouldShow(defaults: defaults, version: "1.1 (2)"), "a new version gets its splash again")
    }
}

final class ChipPaletteTests: XCTestCase {
    func testEveryChipHasADistinctLetterSoColourIsNeverTheOnlyCue() {
        let letters = allChipColors.map(ChipPalette.initial)
        XCTAssertEqual(letters, ["W", "R", "B", "G", "K"])
        XCTAssertEqual(Set(letters).count, allChipColors.count)
    }
}
