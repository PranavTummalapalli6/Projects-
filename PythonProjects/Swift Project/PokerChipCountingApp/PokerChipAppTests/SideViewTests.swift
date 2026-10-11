//
//  SideViewTests.swift
//  PokerChipAppTests
//
//  Counting chips from a photo taken from the side: how the camera was held, what
//  is sent, what comes back, and what correcting a pile does to the counts.
//

import ImageIO
import XCTest
@testable import PokerChipApp

// MARK: - How the camera was held

final class CameraPoseTests: XCTestCase {
    /// The accelerometer vector stored in each of seven real photos (one chip set, shot
    /// landscape: EXIF orientation 1), and the tilt and roll each should give.
    private let samplePhotos: [(gravity: (Double, Double, Double), pitch: Double, roll: Double)] = [
        ((-0.9611233, -0.008555597, -0.2753454), 15.99, -0.51),
        ((-0.9401841, 0.07399677, -0.3135168), 18.39, 4.50),
        ((-0.9266381, -0.1062867, -0.3589559), 21.05, -6.54),
        ((-0.9059019, 0.005503764, -0.4060475), 24.14, 0.35),
        ((-0.9582989, 0.02408891, -0.275961), 16.06, 1.44),
        ((-0.9018812, 0.3136215, -0.2667736), 15.61, 19.17),
        ((-0.9281884, -0.09408633, -0.351437), 20.64, -5.79),
    ]

    func testTheSevenSamplePhotosGiveTheirRealTiltAndRoll() throws {
        for sample in samplePhotos {
            let pose = try XCTUnwrap(CameraPose(gravity: sample.gravity, orientation: 1, focal35mm: 24))
            XCTAssertEqual(pose.pitchDegrees, sample.pitch, accuracy: 0.1)
            XCTAssertEqual(try XCTUnwrap(pose.rollDegrees), sample.roll, accuracy: 0.1)
            XCTAssertEqual(pose.focal35mm, 24)
        }
    }

    func testAPhoneHeldLevelLooksStraightOutAndOneLyingFlatLooksStraightDown() throws {
        let level = try XCTUnwrap(CameraPose(gravity: (0, -1, 0), orientation: 6, focal35mm: nil))
        XCTAssertEqual(level.pitchDegrees, 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(level.rollDegrees), 0, accuracy: 0.001, "upright portrait: nothing is tilted")

        let flat = try XCTUnwrap(CameraPose(gravity: (0, 0, -1), orientation: 1, focal35mm: nil))
        XCTAssertEqual(flat.pitchDegrees, 90, accuracy: 0.001)
    }

    func testTheSameSceneGivesTheSameRollHoweverThePhoneWasHeld() throws {
        // Photo 5 above, as the phone would have written it had it been turned a quarter or a half turn.
        let (x, y, z) = (-0.9018812, 0.3136215, -0.2667736)
        let turned: [(orientation: Int, gravity: (Double, Double, Double))] = [
            (1, (x, y, z)),
            (6, (-y, x, z)),     // portrait, upright
            (3, (-x, -y, z)),    // landscape, the other way up
            (8, (y, -x, z)),     // portrait, upside down
        ]
        for item in turned {
            let pose = try XCTUnwrap(CameraPose(gravity: item.gravity, orientation: item.orientation, focal35mm: nil))
            XCTAssertEqual(pose.pitchDegrees, 15.6, accuracy: 0.2, "orientation \(item.orientation)")
            XCTAssertEqual(try XCTUnwrap(pose.rollDegrees), 19.2, accuracy: 0.2, "orientation \(item.orientation)")
        }
    }

    func testAnUnknownOrMirroredOrientationStillGivesTheTiltButNotTheRoll() throws {
        for orientation in [nil, 2, 4, 5, 7, 99] as [Int?] {
            let pose = try XCTUnwrap(CameraPose(gravity: (-0.95, 0.1, -0.3), orientation: orientation, focal35mm: nil))
            XCTAssertEqual(pose.pitchDegrees, 17.5, accuracy: 0.5)
            XCTAssertNil(pose.rollDegrees)
        }
    }

    func testAShakenPhoneGivesNoPoseAtAll() {
        XCTAssertNil(CameraPose(gravity: (-2.2, 0.1, -0.3), orientation: 1, focal35mm: nil))
        XCTAssertNil(CameraPose(gravity: (0, 0, 0), orientation: 1, focal35mm: nil))
    }

    func testALensLengthThatCannotBeRightIsLeftOut() throws {
        XCTAssertNil(try XCTUnwrap(CameraPose(gravity: (-1, 0, 0), orientation: 1, focal35mm: 2)).focal35mm)
        XCTAssertNil(try XCTUnwrap(CameraPose(gravity: (-1, 0, 0), orientation: 1, focal35mm: 900)).focal35mm)
        XCTAssertEqual(try XCTUnwrap(CameraPose(gravity: (-1, 0, 0), orientation: 1, focal35mm: 26)).focal35mm, 26)
    }

    // MARK: Reading it out of a photo's metadata

    private func metadata(vector: [Any], orientation: Any? = 1, focal: Any? = 24) -> [String: Any] {
        var result: [String: Any] = [kCGImagePropertyMakerAppleDictionary as String: ["8": vector, "1": 5]]
        if let orientation { result[kCGImagePropertyOrientation as String] = orientation }
        if let focal { result[kCGImagePropertyExifDictionary as String] = [kCGImagePropertyExifFocalLenIn35mmFilm as String: focal] }
        return result
    }

    func testThePoseIsReadFromTheCamerasMetadataWhetherNumbersOrStrings() throws {
        let fromNumbers = try XCTUnwrap(CameraPose.from(metadata: metadata(vector: [NSNumber(value: -0.9611233), NSNumber(value: -0.008555597), NSNumber(value: -0.2753454)], orientation: NSNumber(value: 1))))
        let fromStrings = try XCTUnwrap(CameraPose.from(metadata: metadata(vector: ["-0.9611233", "-0.008555597", "-0.2753454"])))
        XCTAssertEqual(fromNumbers, fromStrings)
        XCTAssertEqual(fromNumbers.pitchDegrees, 16, accuracy: 0.1)
        XCTAssertEqual(fromNumbers.focal35mm, 24)
    }

    func testPhotosWithoutTheCamerasReadingHaveNoPose() {
        XCTAssertNil(CameraPose.from(metadata: [:]))
        XCTAssertNil(CameraPose.from(metadata: [kCGImagePropertyExifDictionary as String: ["x": 1]]))
        XCTAssertNil(CameraPose.from(metadata: metadata(vector: [1, 2])), "a vector has three parts")
        XCTAssertNil(CameraPose.from(metadata: metadata(vector: ["a", "b", "c"])))
        XCTAssertNil(CameraPose.from(imageData: Data("not an image".utf8)))
    }

    func testAPhotoThatSaysNothingAboutItsOrientationHasNoRoll() throws {
        let pose = try XCTUnwrap(CameraPose.from(metadata: metadata(vector: [-0.95, 0.1, -0.3], orientation: nil)))
        XCTAssertNil(pose.rollDegrees)
        XCTAssertEqual(pose.pitchDegrees, 17.5, accuracy: 0.5)
    }
}

// MARK: - What is sent

final class SideViewUploadTests: XCTestCase {
    private let result = #"{"counts": {}, "confidence": "low", "photoUrl": ""}"#

    private func upload(angle: PhotoAngle, pose: CameraPose?, colors: [String] = []) async throws -> String {
        let script = Script([.respond(status: 200, body: result)])
        _ = try await script.client().uploadPhoto(
            image: UITestSamplePhoto.image(width: 300, height: 225), denominations: ["White": 0.25], sessionId: "night-1",
            angle: angle, pose: pose, colors: colors
        )
        let body = try XCTUnwrap(script.requests.last?.httpBody)
        // The photo's bytes aren't text; the form's own fields are.
        return String(decoding: body, as: UTF8.self)
    }

    private func field(_ name: String, _ value: String) -> String { "name=\"\(name)\"\r\n\r\n\(value)\r\n" }

    func testAPhotoFromAboveSendsNothingAboutHowItWasTaken() async throws {
        let text = try await upload(angle: .above, pose: CameraPose(gravity: (-0.95, 0.1, -0.3), orientation: 1, focal35mm: 24), colors: ["Red"])
        XCTAssertFalse(text.contains("name=\"view\""))
        XCTAssertFalse(text.contains("name=\"pitch\""))
        XCTAssertFalse(text.contains("name=\"colors\""))
        XCTAssertTrue(text.contains("name=\"denominations\""))
    }

    func testAPhotoFromTheSideSendsTheViewThePoseAndTheColoursInPlay() async throws {
        let pose = try XCTUnwrap(CameraPose(gravity: (-0.9611233, -0.008555597, -0.2753454), orientation: 1, focal35mm: 24))
        let text = try await upload(angle: .side, pose: pose, colors: ["Red", "Green"])
        XCTAssertTrue(text.contains(field("view", "side")), text)
        XCTAssertTrue(text.contains(field("pitch", "16.0")))
        XCTAssertTrue(text.contains(field("roll", "-0.5")))
        XCTAssertTrue(text.contains(field("focal35", "24")))
        XCTAssertTrue(text.contains(field("colors", "Red,Green")))
    }

    func testWithoutAPoseOrARollOnlyWhatIsKnownIsSent() async throws {
        let noPose = try await upload(angle: .side, pose: nil)
        XCTAssertTrue(noPose.contains(field("view", "side")))
        XCTAssertFalse(noPose.contains("name=\"pitch\""))
        XCTAssertFalse(noPose.contains("name=\"colors\""))

        let noRoll = try await upload(angle: .side, pose: CameraPose(gravity: (-0.95, 0.1, -0.3), orientation: nil, focal35mm: nil))
        XCTAssertTrue(noRoll.contains("name=\"pitch\""))
        XCTAssertFalse(noRoll.contains("name=\"roll\""))
        XCTAssertFalse(noRoll.contains("name=\"focal35\""))
    }
}

// MARK: - What comes back

final class StackDecodingTests: XCTestCase {
    func testPilesAreReadWhenThereAreSome() throws {
        let json = #"{"counts": {"Red": 3}, "confidence": "low", "photoUrl": "", "detections": [], "view": "side", "stacks": [{"x": 0.3, "y": 0.4, "w": 0.15, "h": 0.09, "angle": -4.5, "color": "Red", "count": 3, "confidence": "low"}]}"#
        let result = try JSONDecoder().decode(ChipDetectionResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.view, "side")
        XCTAssertEqual(result.stacks, [StackDetection(x: 0.3, y: 0.4, w: 0.15, h: 0.09, angle: -4.5, color: "Red", count: 3, confidence: "low")])
    }

    func testAnOlderServerAnswersAsIfFromAbove() throws {
        let json = #"{"counts": {"White": 2}, "confidence": "high", "photoUrl": ""}"#
        let result = try JSONDecoder().decode(ChipDetectionResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.view, "top")
        XCTAssertTrue(result.stacks.isEmpty)
    }

    func testMalformedPilesNeverCostThePersonTheirCounts() throws {
        let json = #"{"counts": {"Red": 3}, "confidence": "low", "photoUrl": "", "view": 7, "stacks": "what"}"#
        let result = try JSONDecoder().decode(ChipDetectionResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.counts, ["Red": 3])
        XCTAssertEqual(result.view, "top")
        XCTAssertTrue(result.stacks.isEmpty)
    }

    func testAPileIsDrawnTurnedTheScreensWayNotOpenCVs() {
        let mark = StackMark(StackDetection(x: 0.3, y: 0.4, w: 0.15, h: 0.09, angle: -12, color: "Red", count: 0, confidence: "low"))
        XCTAssertEqual(mark.angle, 12, "the service turns boxes counter-clockwise, the screen clockwise")
        XCTAssertEqual(mark.count, 1, "a pile is at least one chip")
        XCTAssertEqual(mark.confidence, "low")
    }
}

// MARK: - A photo from the side, corrected

@MainActor
final class CashOutSideViewTests: XCTestCase {
    private func night(colors: [String] = ["White", "Red", "Blue", "Green", "Black"]) -> GameNight {
        let values = ["White": 25, "Red": 100, "Blue": 200, "Green": 500, "Black": 1_000]
        return GameNight.start(
            now: Date(timeIntervalSince1970: 1_786_042_800), buyInMinor: 5_000, playerNames: ["Sam", "Alex"],
            colors: colors, denominationsMinor: values.filter { colors.contains($0.key) }
        )
    }

    private func viewModel(_ night: GameNight? = nil, client: ChipVisionAPIClient) -> CashOutViewModel {
        let night = night ?? self.night()
        let model = CashOutViewModel(target: CashOutTarget(nightID: night.id, playerID: night.players[0].id), night: night, client: client)
        model.photoAngle = .side
        return model
    }

    /// The service's answer for the sample photo taken from the side.
    private var sideResponse: Script.Step {
        let stacks = UITestSamplePhoto.sidePiles.map { pile -> String in
            let box = UITestSamplePhoto.sideBox(for: pile)
            return #"{"x": \#(box.x), "y": \#(box.y), "w": \#(box.w), "h": \#(box.h), "angle": -3.0, "color": "\#(pile.color)", "count": \#(pile.count), "confidence": "low"}"#
        }.joined(separator: ",")
        let counts = UITestSamplePhoto.sidePiles.map { #""\#($0.color)": \#($0.count)"# }.joined(separator: ",")
        return .respond(status: 200, body: #"{"counts": {\#(counts)}, "confidence": "low", "photoUrl": "", "detections": [], "view": "side", "stacks": [\#(stacks)]}"#)
    }

    private func counted(_ model: CashOutViewModel) async {
        await model.submitPhoto(UITestSamplePhoto.sideImage(width: 400, height: 300), pose: UITestSamplePhoto.samplePose).value
    }

    func testThePhotoComesBackAsPilesAndTheCountsAreTheirTotals() async throws {
        let model = viewModel(client: Script([sideResponse]).client())
        await counted(model)

        let capture = try XCTUnwrap(model.captures.first)
        XCTAssertEqual(capture.angle, .side)
        XCTAssertEqual(capture.stacks.count, 5)
        XCTAssertTrue(capture.marks.isEmpty)
        XCTAssertEqual(capture.tally, UITestSamplePhoto.sideTally)
        XCTAssertEqual(capture.chipCount, 15)
        XCTAssertEqual(model.counts, UITestSamplePhoto.sideTally)
        XCTAssertEqual(model.photoNotice, .counted(confidence: "low", ignored: 0))
    }

    func testTheRequestCarriesTheCamerasPoseAndTheNightsColours() async throws {
        let script = Script([sideResponse])
        let model = viewModel(client: script.client())
        await counted(model)

        let body = String(decoding: try XCTUnwrap(script.requests.last?.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"view\"\r\n\r\nside"))
        XCTAssertTrue(body.contains("name=\"pitch\""))
        XCTAssertTrue(body.contains("name=\"colors\"\r\n\r\nWhite,Red,Blue,Green,Black"))
    }

    func testAPileInAColourTheNightDoesntUseGetsNoBoxAndIsReportedLeftOut() async throws {
        let model = viewModel(night(colors: ["White", "Red"]), client: Script([sideResponse]).client())
        await counted(model)

        let capture = try XCTUnwrap(model.captures.first)
        XCTAssertEqual(capture.stacks.map(\.color), ["White", "Red"])
        XCTAssertEqual(model.counts, ["White": 4, "Red": 3])
        XCTAssertEqual(model.photoNotice, .counted(confidence: "low", ignored: 8), "2 blue, 5 green and 1 black were left out")
    }

    func testAServerThatCannotReadTheSideIsNotBelieved() async throws {
        // An older service reads every photo as circles; it would call each pile a single chip.
        let model = viewModel(client: Script([.respond(status: 200, body: #"{"counts": {"White": 1}, "confidence": "high", "photoUrl": "", "detections": [{"x": 0.2, "y": 0.2, "r": 0.04, "color": "White"}]}"#)]).client())
        await counted(model)

        XCTAssertTrue(model.captures.isEmpty)
        XCTAssertEqual(model.counts.values.reduce(0, +), 0)
        guard case .failed(let message)? = model.photoNotice else { return XCTFail("expected a failure notice, got \(String(describing: model.photoNotice))") }
        XCTAssertTrue(message.contains("from the side"))
    }

    func testAPhotoFromAboveIsStillReadAsCircles() async throws {
        let model = viewModel(client: Script([.respond(status: 200, body: #"{"counts": {"White": 1}, "confidence": "high", "photoUrl": "", "detections": [{"x": 0.2, "y": 0.2, "r": 0.04, "color": "White"}]}"#)]).client())
        model.photoAngle = .above
        await counted(model)

        let capture = try XCTUnwrap(model.captures.first)
        XCTAssertEqual(capture.angle, .above)
        XCTAssertEqual(capture.marks.count, 1)
        XCTAssertTrue(capture.stacks.isEmpty)
    }

    // MARK: Correcting a pile

    private func counted() async throws -> (CashOutViewModel, UUID) {
        let model = viewModel(client: Script([sideResponse]).client())
        await counted(model)
        return (model, try XCTUnwrap(model.captures.first).id)
    }

    private func pile(_ color: String, in model: CashOutViewModel) throws -> StackMark {
        try XCTUnwrap(model.captures.first?.stacks.first { $0.color == color })
    }

    func testChangingHowManyChipsAreInAPileMovesTheCountByTheDifference() async throws {
        let (model, captureID) = try await counted()
        let red = try pile("Red", in: model)

        model.setStackCount(red.id, in: captureID, to: 7)
        XCTAssertEqual(model.counts["Red"], 7)
        XCTAssertEqual(try pile("Red", in: model).count, 7)
        XCTAssertEqual(model.counts["Green"], 5, "nothing else moves")

        model.setStackCount(red.id, in: captureID, to: 2)
        XCTAssertEqual(model.counts["Red"], 2)
    }

    func testAPileHoldsAtLeastOneChipAndAtMostTheLimit() async throws {
        let (model, captureID) = try await counted()
        let red = try pile("Red", in: model)

        model.setStackCount(red.id, in: captureID, to: 0)
        XCTAssertEqual(try pile("Red", in: model).count, 1)
        XCTAssertEqual(model.counts["Red"], 1)

        model.setStackCount(red.id, in: captureID, to: 5_000)
        XCTAssertEqual(try pile("Red", in: model).count, StackMark.largest)
        XCTAssertEqual(model.counts["Red"], StackMark.largest)
    }

    func testRecolouringAPileMovesAllItsChipsToTheNewColour() async throws {
        let (model, captureID) = try await counted()
        let green = try pile("Green", in: model)

        model.recolorStack(green.id, in: captureID, to: "Black")
        XCTAssertEqual(model.counts["Green"], 0)
        XCTAssertEqual(model.counts["Black"], 6, "5 green and the 1 black that was there")
        XCTAssertEqual(try XCTUnwrap(model.captures.first).tally["Black"], 6)

        model.recolorStack(green.id, in: captureID, to: "Purple")
        XCTAssertEqual(model.counts["Black"], 6, "a colour the night doesn't use changes nothing")
    }

    func testRemovingAPileTakesItsChipsOffTheCounts() async throws {
        let (model, captureID) = try await counted()
        model.removeStack(try pile("Blue", in: model).id, in: captureID)

        XCTAssertEqual(model.counts["Blue"], 0)
        XCTAssertEqual(try XCTUnwrap(model.captures.first).stacks.count, 4)
        XCTAssertEqual(model.counts.values.reduce(0, +), 13)
    }

    func testAddingAPileStartsItAtOneChipDrawnAsBigAsTheOthers() async throws {
        let (model, captureID) = try await counted()
        let id = try XCTUnwrap(model.addStack(in: captureID, x: 0.4, y: 0.3, color: "Blue"))

        let added = try XCTUnwrap(model.captures.first?.stacks.first { $0.id == id })
        XCTAssertEqual(added.count, 1)
        XCTAssertNil(added.confidence, "a person put it there")
        XCTAssertEqual(model.counts["Blue"], 3)
        let others = try XCTUnwrap(model.captures.first).stacks.filter { $0.id != id }
        XCTAssertTrue(others.map(\.w).contains(added.w), "the median width of the others")
        XCTAssertNil(model.addStack(in: captureID, x: 0.4, y: 0.3, color: "Purple"))
        XCTAssertNil(model.addStack(in: UUID(), x: 0.4, y: 0.3, color: "Blue"))
    }

    func testWhateverIsDoneToThePilesTheCountsStayInStepWithThem() async throws {
        let (model, captureID) = try await counted()
        var rng = SplitMix64(seed: 2_027)
        let colors = model.colors

        for step in 0..<600 {
            let stacks = try XCTUnwrap(model.captures.first).stacks
            switch Int.random(in: 0..<4, using: &rng) {
            case 0 where !stacks.isEmpty:
                model.setStackCount(stacks[Int.random(in: 0..<stacks.count, using: &rng)].id, in: captureID, to: Int.random(in: -3...120, using: &rng))
            case 1 where !stacks.isEmpty:
                model.recolorStack(stacks[Int.random(in: 0..<stacks.count, using: &rng)].id, in: captureID, to: colors[Int.random(in: 0..<colors.count, using: &rng)])
            case 2 where !stacks.isEmpty:
                model.removeStack(stacks[Int.random(in: 0..<stacks.count, using: &rng)].id, in: captureID)
            default:
                model.addStack(in: captureID, x: Double.random(in: 0...1, using: &rng), y: Double.random(in: 0...0.75, using: &rng), color: colors[Int.random(in: 0..<colors.count, using: &rng)])
            }
            let tally = try XCTUnwrap(model.captures.first).tally
            for color in colors {
                XCTAssertEqual(model.counts[color], tally[color] ?? 0, "step \(step): \(color)")
            }
        }
    }

    func testStartingOverForgetsThePilesToo() async throws {
        let (model, _) = try await counted()
        model.startOver()
        XCTAssertTrue(model.captures.isEmpty)
        XCTAssertEqual(model.counts.values.reduce(0, +), 0)
    }

    // MARK: The sample photo the UI tests use

    func testTheSampleSidePhotoPassesTheCheckOnThePhone() throws {
        let report = try XCTUnwrap(PhotoQuality.assess(UITestSamplePhoto.sideImage()))
        XCTAssertTrue(report.isGood, "\(report)")
    }

    func testEverySamplePileFitsInsideTheSamplePhoto() {
        for pile in UITestSamplePhoto.sidePiles {
            let box = UITestSamplePhoto.sideBox(for: pile)
            XCTAssertGreaterThan(box.x - box.w / 2, 0, pile.color)
            XCTAssertLessThan(box.x + box.w / 2, 1, pile.color)
            XCTAssertGreaterThan(box.y - box.h / 2, 0, pile.color)
            XCTAssertLessThan(box.y + box.h / 2, 0.75, pile.color)
        }
    }

    func testTheAdviceFollowsHowTheChipsAreLaidOut() {
        XCTAssertTrue(ReviewCountsView.photoAdvice(for: .above, hasPhotos: false).contains("directly overhead"))
        XCTAssertTrue(ReviewCountsView.photoAdvice(for: .side, hasPhotos: false).contains("low"))
        XCTAssertEqual(ReviewCountsView.photoAdvice(for: .side, hasPhotos: true), ReviewCountsView.photoAdvice(for: .above, hasPhotos: true))
        XCTAssertNotEqual(PhotoQuality.Issue.blurry.message(for: .side), PhotoQuality.Issue.blurry.message(for: .above))
        XCTAssertNotEqual(FramingGuideView.advice(for: .side), FramingGuideView.advice(for: .above))
    }
}
