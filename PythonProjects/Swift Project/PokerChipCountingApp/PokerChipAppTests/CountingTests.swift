//
//  CountingTests.swift
//  PokerChipAppTests
//
//  Counting chips from photos: a photo that won't count well is caught before it
//  is sent, every chip found gets a circle that can be fixed, a second photo adds
//  to the first, and none of it is needed to count by hand.
//

import XCTest
import CoreImage
@testable import PokerChipApp

private let t0 = Date(timeIntervalSince1970: 1_786_042_800)

private func nightWithAllColours() -> GameNight {
    GameNight.start(
        now: t0, buyInMinor: 5_000, playerNames: ["Sam", "Alex"],
        colors: ["White", "Red", "Blue", "Green", "Black"],
        denominationsMinor: ["White": 25, "Red": 100, "Blue": 200, "Green": 500, "Black": 1_000],
        startingCounts: ["White": 20, "Red": 10, "Blue": 5, "Green": 2, "Black": 1]
    )
}

// MARK: - Is the photo worth sending?

final class PhotoQualityTests: XCTestCase {
    private func cgImage(_ image: UIImage) throws -> CGImage { try XCTUnwrap(image.cgImage) }

    private func flat(_ gray: CGFloat, width: CGFloat = 1000, height: CGFloat = 750) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor(white: gray, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func blurred(_ image: UIImage, sigma: Double) throws -> UIImage {
        let input = try XCTUnwrap(CIImage(image: image))
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: input.extent)
        let result = try XCTUnwrap(CIContext().createCGImage(output, from: input.extent))
        return UIImage(cgImage: result)
    }

    func testASharpPhotoOfChipsIsFine() throws {
        let report = try XCTUnwrap(PhotoQuality.assess(UITestSamplePhoto.image()))
        XCTAssertTrue(report.isGood, "\(report)")
        XCTAssertGreaterThan(report.sharpness, PhotoQuality.minimumSharpness * 2, "well clear of the line, not just over it")
        XCTAssertEqual(report.pixelWidth, 1_200)
    }

    func testTheSamePhotoBlurredIsCalledBlurry() throws {
        let report = try XCTUnwrap(PhotoQuality.assess(try blurred(UITestSamplePhoto.image(), sigma: 14)))
        XCTAssertEqual(report.issues, [.blurry], "\(report)")
        XCTAssertLessThan(report.sharpness, PhotoQuality.minimumSharpness)
    }

    func testBlurringMakesAPhotoLessSharpStepByStep() throws {
        let sharp = UITestSamplePhoto.image()
        let scores = try [0.0, 2, 6, 14].map { sigma -> Double in
            let image = try sigma == 0 ? sharp : blurred(sharp, sigma: sigma)
            return try XCTUnwrap(PhotoQuality.assess(image)).sharpness
        }
        XCTAssertEqual(scores, scores.sorted(by: >), "\(scores)")
    }

    func testAVeryDarkPhotoIsCalledDarkNotBlurry() throws {
        let report = try XCTUnwrap(PhotoQuality.assess(flat(0.05)))
        XCTAssertEqual(report.issues, [.tooDark], "a dark photo has no contrast to be sharp with: fix the light first")
        XCTAssertLessThan(report.brightness, PhotoQuality.darkestBrightness)
    }

    func testAWashedOutPhotoIsCalledTooBright() throws {
        let report = try XCTUnwrap(PhotoQuality.assess(flat(0.97)))
        XCTAssertEqual(report.issues, [.tooBright])
    }

    func testAFlatMidGreyPhotoIsBlurry() throws {
        XCTAssertEqual(try XCTUnwrap(PhotoQuality.assess(flat(0.5))).issues, [.blurry])
    }

    func testASmallPhotoIsCalledSmall() throws {
        let small = try XCTUnwrap(PhotoQuality.assess(UITestSamplePhoto.image(width: 480, height: 360)))
        XCTAssertTrue(small.issues.contains(.lowResolution), "\(small)")
        XCTAssertEqual(small.pixelWidth, 480)
    }

    func testSeveralProblemsAreListedWithTheMostUsefulFirst() throws {
        let report = try XCTUnwrap(PhotoQuality.assess(flat(0.02, width: 400, height: 300)))
        XCTAssertEqual(report.issues, [.tooDark, .lowResolution])
    }

    func testEveryIssueTellsThePersonWhatToDo() {
        for issue in [PhotoQuality.Issue.blurry, .tooDark, .tooBright, .lowResolution] {
            XCTAssertFalse(issue.message.isEmpty)
            XCTAssertTrue(issue.message.contains("try again") || issue.message.contains("will count better"), issue.message)
        }
    }

    func testMeasuringByHandOnTinyPictures() {
        let flatPicture = [UInt8](repeating: 100, count: 25)
        let flatResult = PhotoQuality.measure(luma: flatPicture, width: 5, height: 5)
        XCTAssertEqual(flatResult.sharpness, 0, accuracy: 0.0001)
        XCTAssertEqual(flatResult.brightness, 100, accuracy: 0.0001)

        // A checkerboard has the sharpest edges a picture can have.
        let checker = (0..<25).map { ($0 / 5 + $0 % 5) % 2 == 0 ? UInt8(0) : UInt8(255) }
        XCTAssertGreaterThan(PhotoQuality.measure(luma: checker, width: 5, height: 5).sharpness, 100_000)

        XCTAssertEqual(PhotoQuality.measure(luma: [1, 2], width: 5, height: 5).sharpness, 0, "too few pixels is not a crash")
    }

    func testAnImageWithNoPixelsIsSimplyUsed() {
        XCTAssertNil(PhotoQuality.assess(UIImage()))
    }
}

// MARK: - What the server sends back

final class DetectionDecodingTests: XCTestCase {
    func testCirclesAreReadWhenThereAreSome() throws {
        let json = #"{"counts": {"White": 2}, "confidence": "high", "photoUrl": "", "detections": [{"x": 0.25, "y": 0.5, "r": 0.04, "color": "White"}, {"x": 0.6, "y": 0.3, "r": 0.05, "color": "White"}]}"#
        let result = try JSONDecoder().decode(ChipDetectionResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.detections.count, 2)
        XCTAssertEqual(result.detections.first, ChipDetection(x: 0.25, y: 0.5, r: 0.04, color: "White"))
    }

    func testAnOlderServerWithoutCirclesStillWorks() throws {
        let json = #"{"counts": {"White": 2}, "confidence": "high", "photoUrl": ""}"#
        let result = try JSONDecoder().decode(ChipDetectionResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.counts, ["White": 2])
        XCTAssertTrue(result.detections.isEmpty)
    }

    func testMalformedCirclesNeverCostThePersonTheirCounts() throws {
        let json = #"{"counts": {"White": 2}, "confidence": "low", "photoUrl": "", "detections": "what"}"#
        let result = try JSONDecoder().decode(ChipDetectionResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.counts, ["White": 2])
        XCTAssertTrue(result.detections.isEmpty)
    }

    func testTheCountsThemselvesAreStillRequired() {
        let json = #"{"confidence": "low", "photoUrl": ""}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ChipDetectionResult.self, from: Data(json.utf8)))
    }
}

// MARK: - A photo, circled

@MainActor
final class CashOutPhotoTests: XCTestCase {
    private func viewModel(_ night: GameNight? = nil, client: ChipVisionAPIClient) -> CashOutViewModel {
        let night = night ?? nightWithAllColours()
        return CashOutViewModel(target: CashOutTarget(nightID: night.id, playerID: night.players[0].id), night: night, client: client)
    }

    /// The server's answer for the sample photo.
    private var sampleResponse: Script.Step {
        let detections = UITestSamplePhoto.chips.map {
            #"{"x": \#($0.x), "y": \#($0.y), "r": \#(UITestSamplePhoto.radius), "color": "\#($0.color)"}"#
        }.joined(separator: ",")
        return .respond(status: 200, body: #"{"counts": {"White": 10, "Red": 7, "Blue": 5, "Green": 3, "Black": 2}, "confidence": "high", "photoUrl": "", "detections": [\#(detections)]}"#)
    }

    private func counted(_ model: CashOutViewModel) async {
        await model.submitPhoto(UITestSamplePhoto.image(width: 400, height: 300)).value
    }

    // MARK: Circles

    func testThePhotoComesBackWithACircleOnEveryChipFound() async throws {
        let model = viewModel(client: Script([sampleResponse]).client())
        await counted(model)

        let capture = try XCTUnwrap(model.captures.first)
        XCTAssertEqual(capture.marks.count, 27)
        XCTAssertEqual(capture.tally, ["White": 10, "Red": 7, "Blue": 5, "Green": 3, "Black": 2])
        XCTAssertEqual(model.counts, capture.tally)
        XCTAssertEqual(model.photoNotice, .counted(confidence: "high", ignored: 0))
    }

    func testAChipInAColourTheNightDoesntUseGetsNoCircleAndIsReportedLeftOut() async throws {
        let night = GameNight.start(now: t0, buyInMinor: 2_500, playerNames: ["Sam", "Alex"], colors: ["White", "Red"], denominationsMinor: ["White": 25, "Red": 100])
        let model = viewModel(night, client: Script([sampleResponse]).client())
        await counted(model)

        let capture = try XCTUnwrap(model.captures.first)
        XCTAssertEqual(capture.marks.count, 17, "10 white and 7 red")
        XCTAssertEqual(Set(capture.marks.map(\.color)), ["White", "Red"])
        XCTAssertEqual(model.counts, ["White": 10, "Red": 7])
        XCTAssertEqual(model.photoNotice, .counted(confidence: "high", ignored: 10), "5 blue, 3 green and 2 black were left out")
    }

    func testAnOlderServerStillCountsButThereIsNothingToCheck() async throws {
        let model = viewModel(client: Script([.respond(status: 200, body: #"{"counts": {"White": 4}, "confidence": "medium", "photoUrl": ""}"#)]).client())
        await counted(model)
        XCTAssertEqual(model.counts["White"], 4)
        XCTAssertEqual(try XCTUnwrap(model.captures.first).marks.count, 0)
    }

    func testAFailedPhotoLeavesNoPhotoBehind() async {
        let model = viewModel(client: Script([.fail(URLError(.notConnectedToInternet))]).client())
        model.counts["Red"] = 3
        await counted(model)
        XCTAssertTrue(model.captures.isEmpty)
        XCTAssertEqual(model.counts["Red"], 3)
    }

    // MARK: Fixing a circle

    func testChangingAChipsColourMovesOneCountToTheOther() async throws {
        let model = viewModel(client: Script([sampleResponse]).client())
        await counted(model)
        let capture = try XCTUnwrap(model.captures.first)
        let mark = try XCTUnwrap(capture.marks.first { $0.color == "Red" })

        model.recolor(mark.id, in: capture.id, to: "Blue")

        XCTAssertEqual(model.counts["Red"], 6)
        XCTAssertEqual(model.counts["Blue"], 6)
        XCTAssertEqual(model.captures.first?.marks.first { $0.id == mark.id }?.color, "Blue")
        XCTAssertEqual(model.cashOutMinor, 10 * 25 + 6 * 100 + 6 * 200 + 3 * 500 + 2 * 1_000, "and so does the cash-out")
    }

    func testRecolouringToTheSameColourOrAColourNotInPlayDoesNothing() async throws {
        let model = viewModel(client: Script([sampleResponse]).client())
        await counted(model)
        let capture = try XCTUnwrap(model.captures.first)
        let mark = try XCTUnwrap(capture.marks.first)
        let before = model.counts

        model.recolor(mark.id, in: capture.id, to: mark.color)
        model.recolor(mark.id, in: capture.id, to: "Purple")

        XCTAssertEqual(model.counts, before)
        XCTAssertEqual(model.captures.first?.marks.first { $0.id == mark.id }?.color, mark.color)
    }

    func testRemovingACircleTakesOneOffItsColour() async throws {
        let model = viewModel(client: Script([sampleResponse]).client())
        await counted(model)
        let capture = try XCTUnwrap(model.captures.first)
        let mark = try XCTUnwrap(capture.marks.first { $0.color == "Black" })

        model.removeMark(mark.id, in: capture.id)

        XCTAssertEqual(model.counts["Black"], 1)
        XCTAssertEqual(model.captures.first?.marks.count, 26)
    }

    func testAddingAChipPutsACircleWhereTheyTappedAndCountsIt() async throws {
        let model = viewModel(client: Script([sampleResponse]).client())
        await counted(model)
        let capture = try XCTUnwrap(model.captures.first)

        let id = try XCTUnwrap(model.addMark(in: capture.id, x: 0.5, y: 0.7, color: "Green"))

        XCTAssertEqual(model.counts["Green"], 4)
        let added = try XCTUnwrap(model.captures.first?.marks.first { $0.id == id })
        XCTAssertEqual(added.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(added.y, 0.7, accuracy: 0.0001)
        XCTAssertEqual(added.r, UITestSamplePhoto.radius, accuracy: 0.0001, "drawn the size the others are")
    }

    func testAddingToAPhotoWithNoCirclesUsesASensibleSize() async throws {
        let model = viewModel(client: Script([.respond(status: 200, body: #"{"counts": {}, "confidence": "low", "photoUrl": ""}"#)]).client())
        await counted(model)
        let capture = try XCTUnwrap(model.captures.first)
        let id = try XCTUnwrap(model.addMark(in: capture.id, x: 0.3, y: 0.3, color: "White"))
        XCTAssertEqual(try XCTUnwrap(model.captures.first?.marks.first { $0.id == id }).r, 0.035, accuracy: 0.0001)
    }

    func testACorrectionNeverTakesACountBelowZero() async throws {
        let model = viewModel(client: Script([sampleResponse]).client())
        await counted(model)
        let capture = try XCTUnwrap(model.captures.first)
        let mark = try XCTUnwrap(capture.marks.first { $0.color == "Black" })

        model.counts["Black"] = 0                    // the person had already zeroed it by hand
        model.removeMark(mark.id, in: capture.id)

        XCTAssertEqual(model.counts["Black"], 0)
    }

    func testEditsToAPhotoOrChipThatIsntThereDoNothing() async throws {
        let model = viewModel(client: Script([sampleResponse]).client())
        await counted(model)
        let capture = try XCTUnwrap(model.captures.first)
        let before = model.counts

        model.recolor(UUID(), in: capture.id, to: "Red")
        model.removeMark(UUID(), in: capture.id)
        model.removeMark(try XCTUnwrap(capture.marks.first).id, in: UUID())
        XCTAssertNil(model.addMark(in: UUID(), x: 0.1, y: 0.1, color: "Red"))
        XCTAssertNil(model.addMark(in: capture.id, x: 0.1, y: 0.1, color: "Purple"))

        XCTAssertEqual(model.counts, before)
        XCTAssertEqual(model.captures.first?.marks.count, 27)
    }

    func testWhateverIsDoneToTheCirclesTheCountsStayInStepWithThem() async throws {
        let model = viewModel(client: Script([sampleResponse]).client())
        await counted(model)
        let captureID = try XCTUnwrap(model.captures.first).id
        var rng = SplitMix64(seed: 2_026)
        let colors = model.colors

        for step in 0..<600 {
            let marks = try XCTUnwrap(model.captures.first).marks
            switch Int.random(in: 0..<3, using: &rng) {
            case 0 where !marks.isEmpty:
                model.recolor(marks[Int.random(in: 0..<marks.count, using: &rng)].id, in: captureID, to: colors[Int.random(in: 0..<colors.count, using: &rng)])
            case 1 where !marks.isEmpty:
                model.removeMark(marks[Int.random(in: 0..<marks.count, using: &rng)].id, in: captureID)
            default:
                model.addMark(in: captureID, x: Double.random(in: 0...1, using: &rng), y: Double.random(in: 0...0.75, using: &rng), color: colors[Int.random(in: 0..<colors.count, using: &rng)])
            }
            let tally = try XCTUnwrap(model.captures.first).tally
            for color in colors {
                XCTAssertEqual(model.counts[color], tally[color] ?? 0, "step \(step): \(color)")
            }
        }
    }

    // MARK: More than one photo

    func testASecondPhotoAddsToTheFirstInsteadOfReplacingIt() async throws {
        let second = Script.Step.respond(status: 200, body: #"{"counts": {"White": 5, "Red": 1}, "confidence": "medium", "photoUrl": "", "detections": [{"x": 0.2, "y": 0.2, "r": 0.04, "color": "White"}]}"#)
        let model = viewModel(client: Script([sampleResponse, second]).client())

        await counted(model)
        await counted(model)

        XCTAssertEqual(model.captures.count, 2)
        XCTAssertEqual(model.counts, ["White": 15, "Red": 8, "Blue": 5, "Green": 3, "Black": 2])
        XCTAssertEqual(model.captures[1].marks.count, 1, "the second photo's circles are its own")
        XCTAssertEqual(model.photoNotice, .counted(confidence: "medium", ignored: 0))
    }

    func testCountsTypedInBetweenPhotosAreKept() async {
        let model = viewModel(client: Script([sampleResponse, sampleResponse]).client())
        await counted(model)
        model.counts["Red"] = 20
        await counted(model)
        XCTAssertEqual(model.counts["Red"], 27)
    }

    func testFixingCirclesOnEitherPhotoKeepsTheTotalsInStep() async throws {
        let model = viewModel(client: Script([sampleResponse, sampleResponse]).client())
        await counted(model)
        await counted(model)
        let first = model.captures[0], second = model.captures[1]

        model.removeMark(try XCTUnwrap(first.marks.first { $0.color == "White" }).id, in: first.id)
        model.addMark(in: second.id, x: 0.5, y: 0.6, color: "Black")

        for color in model.colors {
            let total = model.captures.reduce(0) { $0 + ($1.tally[color] ?? 0) }
            XCTAssertEqual(model.counts[color], total, color)
        }
        XCTAssertEqual(model.counts["White"], 19)
        XCTAssertEqual(model.counts["Black"], 5)
    }

    func testThereIsALimitToHowManyPhotosOneCashOutTakes() async {
        let model = viewModel(client: Script(Array(repeating: sampleResponse, count: 5)).client())
        XCTAssertTrue(model.canAddPhoto)
        for _ in 0..<CashOutViewModel.maxPhotos { await counted(model) }
        XCTAssertEqual(model.captures.count, CashOutViewModel.maxPhotos)
        XCTAssertFalse(model.canAddPhoto)
    }

    func testStartingOverForgetsThePhotosAndTheirCounts() async {
        let model = viewModel(client: Script([sampleResponse]).client())
        await counted(model)
        model.startOver()
        XCTAssertTrue(model.captures.isEmpty)
        XCTAssertNil(model.photoNotice)
        XCTAssertEqual(model.counts.values.reduce(0, +), 0)
        XCTAssertTrue(model.canAddPhoto)
    }

    // MARK: A photo that won't count well

    private func blurryPhoto() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600), format: format).image { context in
            UIColor(white: 0.5, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        }
    }

    func testAGoodPhotoIsCountedStraightAway() async throws {
        let script = Script([sampleResponse])
        let model = viewModel(client: script.client())
        model.receive(UITestSamplePhoto.image())
        XCTAssertNil(model.qualityPrompt)
        XCTAssertTrue(model.isUploading)
        await waitForUpload(model)
        XCTAssertEqual(model.captures.count, 1)
    }

    func testAPoorPhotoIsHeldBackAndNothingIsSent() {
        let script = Script([sampleResponse])
        let model = viewModel(client: script.client())
        model.receive(blurryPhoto())

        XCTAssertEqual(model.qualityPrompt?.issue, .blurry)
        XCTAssertFalse(model.isUploading)
        XCTAssertTrue(script.requests.isEmpty)
        XCTAssertTrue(model.captures.isEmpty)
    }

    func testUsingAHeldPhotoAnywayCountsIt() async {
        let model = viewModel(client: Script([sampleResponse]).client())
        model.receive(blurryPhoto())
        model.useHeldPhotoAnyway()

        XCTAssertNil(model.qualityPrompt)
        await waitForUpload(model)
        XCTAssertEqual(model.captures.count, 1)
    }

    func testDiscardingAHeldPhotoSendsNothing() {
        let script = Script([sampleResponse])
        let model = viewModel(client: script.client())
        model.receive(blurryPhoto())
        model.discardHeldPhoto()

        XCTAssertNil(model.qualityPrompt)
        XCTAssertTrue(script.requests.isEmpty)
        model.useHeldPhotoAnyway()                      // nothing held: nothing happens
        XCTAssertFalse(model.isUploading)
    }

    private func waitForUpload(_ model: CashOutViewModel) async {
        for _ in 0..<200 where model.isUploading { try? await Task.sleep(nanoseconds: 25_000_000) }
    }

    // MARK: Counting by hand

    func testCountingByHandAndSavingNeverTouchTheNetwork() async {
        let script = Script([])                                   // any request at all would be recorded (and would fail)
        let store = NightStore(repository: MemoryNightRepository())
        await store.load()
        let night = store.start(nightWithAllColours())
        let model = viewModel(night, client: script.client())

        model.counts = ["White": 40, "Red": 12, "Blue": 3, "Green": 1, "Black": 0]
        model.mode = .amount
        model.amountText = "75"
        model.mode = .chips
        XCTAssertTrue(model.save(into: store, now: t0))

        XCTAssertTrue(script.requests.isEmpty, "no signal needed: \(script.requests.map { $0.url?.path ?? "" })")
        XCTAssertEqual(store.night(night.id)?.players[0].cashOutMinor, 40 * 25 + 12 * 100 + 3 * 200 + 500)
    }
}

// MARK: - Waking the service

@MainActor
final class PrewarmTests: XCTestCase {
    override func setUp() async throws {
        Prewarm.reset()
    }

    private func waitFor(_ script: Script, requests: Int) async {
        for _ in 0..<200 where script.requests.count < requests { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    func testItAsksOnceAndThenLeavesTheServiceAloneForAWhile() async {
        let script = Script([.respond(status: 200, body: "{}"), .respond(status: 200, body: "{}")])
        let client = script.client()
        let start = Date()

        Prewarm.countingService(now: start, client: client)
        await waitFor(script, requests: 1)
        Prewarm.countingService(now: start.addingTimeInterval(60), client: client)
        Prewarm.countingService(now: start.addingTimeInterval(299), client: client)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(script.requests.count, 1)

        Prewarm.countingService(now: start.addingTimeInterval(301), client: client)
        await waitFor(script, requests: 2)
        XCTAssertEqual(script.requests.count, 2)
    }

    func testItOnlyEverAsksTheHealthEndpointWithNoSignIn() async {
        let script = Script([.respond(status: 200, body: "{}")])
        Prewarm.countingService(client: script.client())
        await waitFor(script, requests: 1)

        XCTAssertEqual(script.requests.first?.url?.path, "/healthz")
        XCTAssertEqual(script.requests.first?.httpMethod, "GET")
        XCTAssertNil(script.requests.first?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(script.requests.first?.httpBody)
        XCTAssertTrue(script.tokenRequests.isEmpty)
    }

    func testAServiceThatIsDownIsNotAnError() async {
        let script = Script([.fail(URLError(.cannotConnectToHost))])
        Prewarm.countingService(client: script.client())
        await waitFor(script, requests: 1)
        XCTAssertEqual(script.requests.count, 1)       // and nothing crashed or surfaced
    }
}
