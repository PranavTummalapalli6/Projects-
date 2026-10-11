//
//  GuidedCameraTests.swift
//  PokerChipAppTests
//
//  What the camera guide says, and when. Everything here is arithmetic on readings;
//  the camera itself can only be tried on a phone.
//

import Combine
import XCTest
@testable import PokerChipApp

final class FramingAdvisorTests: XCTestCase {
    private func good(_ angle: PhotoAngle) -> FramingReading {
        switch angle {
        case .above: return FramingReading(pitchDegrees: 88, rollDegrees: 20, brightness: 110, sharpness: 400, motion: 0.05)
        case .side: return FramingReading(pitchDegrees: 14, rollDegrees: 1.5, brightness: 110, sharpness: 400, motion: 0.05)
        }
    }

    private func issue(_ reading: FramingReading, _ angle: PhotoAngle) -> FramingIssue? {
        FramingAdvisor.advice(for: reading, angle: angle).issue
    }

    func testAGoodPictureIsReadyAndSaysSo() {
        for angle in PhotoAngle.allCases {
            let advice = FramingAdvisor.advice(for: good(angle), angle: angle)
            XCTAssertTrue(advice.isReady, "\(angle)")
            XCTAssertEqual(advice.message, "Looks good. Take the photo.")
        }
    }

    func testNothingIsSaidUntilTheCameraHasAPicture() {
        XCTAssertEqual(issue(FramingReading(), .above), .notReady)
        var noLight = good(.side)
        noLight.brightness = nil
        XCTAssertEqual(issue(noLight, .side), .notReady)
    }

    func testFromTheSideAPhoneHeldOnItsSideOrUpsideDownIsToldToHoldItUpright() {
        for roll in [90.0, -90.0, 180.0, 40.0, -36.0] {
            var reading = good(.side)
            reading.rollDegrees = roll
            XCTAssertEqual(issue(reading, .side), .holdUpright, "roll \(roll)")
        }
        var nearlyUpright = good(.side)
        nearlyUpright.rollDegrees = 34
        XCTAssertEqual(issue(nearlyUpright, .side), .straighten, "turned, but not on its side")
    }

    func testFromAboveTheWayRoundThePhoneIsHeldDoesNotMatter() {
        for roll in [0.0, 34.0, 90.0, -90.0, 180.0, -36.0] {
            var reading = good(.above)
            reading.rollDegrees = roll
            XCTAssertTrue(FramingAdvisor.advice(for: reading, angle: .above).isReady, "roll \(roll)")
        }
    }

    func testTurnMeansNothingWhenTheCameraLooksAlmostStraightDown() {
        // Nearly flat, the lean of gravity across the screen is a hair and its direction is noise: no "hold it upright".
        var steep = good(.side)
        steep.pitchDegrees = 80
        steep.rollDegrees = 120
        XCTAssertEqual(issue(steep, .side), .lower, "it is too steep for a side view, and that is what to say")
        steep.pitchDegrees = 74
        XCTAssertEqual(issue(steep, .side), .holdUpright, "while the lean is still a clear signal, a phone on its side is said so")
    }

    func testADarkOrWashedOutPictureSaysWhatToDo() {
        var reading = good(.above)
        reading.brightness = 30
        XCTAssertEqual(issue(reading, .above), .tooDark)
        XCTAssertTrue(FramingAdvisor.advice(for: reading, angle: .above).message.contains("light"))
        reading.brightness = 240
        XCTAssertEqual(issue(reading, .above), .tooBright)
        reading.brightness = FramingAdvisor.darkestBrightness
        XCTAssertNil(issue(reading, .above), "the edge itself is fine")
    }

    func testTheLightLimitsAreThePhotoChecksOwn() {
        XCTAssertEqual(FramingAdvisor.darkestBrightness, PhotoQuality.darkestBrightness)
        XCTAssertEqual(FramingAdvisor.brightestBrightness, PhotoQuality.brightestBrightness)
    }

    func testFromAboveTheCameraMustLookStraightDown() {
        var reading = good(.above)
        for (pitch, expected) in [(90.0, nil), (72.0, nil), (71.0, FramingIssue.flatten), (40.0, .flatten), (0.0, .flatten)] as [(Double, FramingIssue?)] {
            reading.pitchDegrees = pitch
            XCTAssertEqual(issue(reading, .above), expected, "pitch \(pitch)")
        }
    }

    func testFromTheSideTheCameraIsLowAndLevel() {
        var reading = good(.side)
        for (pitch, expected) in [(14.0, nil), (30.0, nil), (31.0, FramingIssue.lower), (60.0, .lower), (-8.0, nil), (-9.0, .tiltDown)] as [(Double, FramingIssue?)] {
            reading.pitchDegrees = pitch
            XCTAssertEqual(issue(reading, .side), expected, "pitch \(pitch)")
        }
        reading.pitchDegrees = 14
        for (roll, expected) in [(0.0, nil), (5.0, nil), (-5.0, nil), (5.5, FramingIssue.straighten), (-12.0, .straighten)] as [(Double, FramingIssue?)] {
            reading.rollDegrees = roll
            XCTAssertEqual(issue(reading, .side), expected, "roll \(roll)")
        }
    }

    func testPhotosFromAboveAndFromTheSideAreAdvisedDifferently() {
        var steep = good(.side)
        steep.pitchDegrees = 85
        XCTAssertEqual(issue(steep, .side), .lower, "straight down is wrong for a side view")
        XCTAssertNil(issue(steep, .above), "and right for a top view")
        var level = good(.above)
        level.pitchDegrees = 10
        level.rollDegrees = 0
        XCTAssertEqual(issue(level, .above), .flatten)
        XCTAssertNil(issue(level, .side))
    }

    func testWithoutMotionDataTheTiltAdviceIsLeftOut() {
        let reading = FramingReading(pitchDegrees: nil, rollDegrees: nil, brightness: 110, sharpness: 400, motion: nil)
        for angle in PhotoAngle.allCases { XCTAssertNil(issue(reading, angle), "\(angle)") }
    }

    func testAMovingOrSoftPictureIsAskedToHoldStill() {
        var reading = good(.above)
        reading.motion = 1.2
        XCTAssertEqual(issue(reading, .above), .holdStill)

        reading.motion = 0.05
        reading.sharpness = 40
        XCTAssertEqual(issue(reading, .above), .blurry, "still but soft: it won't focus")
        reading.motion = 0.6
        XCTAssertEqual(issue(reading, .above), .holdStill, "soft because it is moving")
        reading.sharpness = 400
        XCTAssertNil(issue(reading, .above), "a little movement over a sharp picture is fine")
    }

    func testTheMostImportantThingIsSaidFirst() {
        var reading = FramingReading(pitchDegrees: 60, rollDegrees: 40, brightness: 20, sharpness: 10, motion: 2)
        XCTAssertEqual(issue(reading, .side), .holdUpright)
        reading.rollDegrees = 10
        XCTAssertEqual(issue(reading, .side), .tooDark)
        reading.brightness = 110
        XCTAssertEqual(issue(reading, .side), .lower)
        reading.pitchDegrees = 14
        XCTAssertEqual(issue(reading, .side), .straighten)
        reading.rollDegrees = 0
        XCTAssertEqual(issue(reading, .side), .holdStill)
        reading.motion = 0
        XCTAssertEqual(issue(reading, .side), .blurry)
    }

    func testEveryMessageIsShortAndPlain() {
        let readings: [(FramingReading, PhotoAngle)] = [
            (FramingReading(), .above),
            (FramingReading(pitchDegrees: 10, rollDegrees: 90, brightness: 110), .side),
            (FramingReading(pitchDegrees: 10, rollDegrees: 0, brightness: 5), .above),
            (FramingReading(pitchDegrees: 10, rollDegrees: 0, brightness: 250), .above),
            (FramingReading(pitchDegrees: 10, rollDegrees: 0, brightness: 110), .above),
            (FramingReading(pitchDegrees: 70, rollDegrees: 0, brightness: 110), .side),
            (FramingReading(pitchDegrees: -20, rollDegrees: 0, brightness: 110), .side),
            (FramingReading(pitchDegrees: 10, rollDegrees: 20, brightness: 110), .side),
            (FramingReading(pitchDegrees: 88, rollDegrees: 0, brightness: 110, motion: 3), .above),
            (FramingReading(pitchDegrees: 88, rollDegrees: 0, brightness: 110, sharpness: 5, motion: 0), .above),
            (FramingReading(pitchDegrees: 88, rollDegrees: 0, brightness: 110, sharpness: 500, motion: 0), .above),
        ]
        var seen = Set<String>()
        for (reading, angle) in readings {
            let message = FramingAdvisor.advice(for: reading, angle: angle).message
            XCTAssertLessThanOrEqual(message.count, 92, message)
            XCTAssertFalse(message.contains("  "), message)
            XCTAssertTrue(message.hasSuffix(".") || message.hasSuffix("…"), message)
            seen.insert(message)
        }
        XCTAssertEqual(seen.count, readings.count, "every situation has words of its own")
    }
}

final class FramingCoachTests: XCTestCase {
    private func reading(pitch: Double = 14, roll: Double = 0, brightness: Double = 110, motion: Double = 0) -> FramingReading {
        FramingReading(pitchDegrees: pitch, rollDegrees: roll, brightness: brightness, sharpness: 400, motion: motion)
    }

    /// Feeds the same reading for `seconds`, ten times a second, starting at `from`; returns the last advice.
    @discardableResult
    private func feed(_ coach: inout FramingCoach, _ reading: FramingReading, from: Double, seconds: Double) -> FramingAdvice {
        var advice = coach.shown
        var t = from
        while t <= from + seconds + 1e-9 {
            advice = coach.update(reading, at: t)
            t += 0.1
        }
        return advice
    }

    func testTheFirstAdviceIsShownAtOnce() {
        var coach = FramingCoach(angle: .side)
        XCTAssertEqual(coach.shown.issue, .notReady)
        XCTAssertEqual(coach.update(reading(pitch: 60), at: 0).issue, .lower, "nobody waits for the first word")
    }

    func testAnIssueThatHoldsIsShownAfterAMoment() {
        var coach = FramingCoach(angle: .side)
        feed(&coach, reading(), from: 0, seconds: 3)                       // settled: ready
        XCTAssertTrue(coach.shown.isReady)
        let advice = feed(&coach, reading(pitch: 60), from: 3.1, seconds: 3)
        XCTAssertEqual(advice.issue, .lower)
    }

    func testAFlickerDoesNotChangeWhatIsShown() {
        var coach = FramingCoach(angle: .side)
        feed(&coach, reading(pitch: 60), from: 0, seconds: 3)              // "lower"
        XCTAssertEqual(coach.shown.issue, .lower)
        // One reading in another state, then back: the advice on show doesn't move.
        coach.update(reading(pitch: 14), at: 3.1)
        XCTAssertEqual(coach.shown.issue, .lower)
        feed(&coach, reading(pitch: 60), from: 3.2, seconds: 1)
        XCTAssertEqual(coach.shown.issue, .lower)
    }

    func testBeingReadyHasToHoldLongerThanAnythingElse() {
        var coach = FramingCoach(angle: .side)
        feed(&coach, reading(pitch: 60), from: 0, seconds: 3)              // "lower"
        // The phone swings level. The average crosses into "right" on the third reading (3.3 s); any other
        // advice would be on screen half a second later, but "ready" must hold for longer than that.
        for step in 1...9 {
            coach.update(reading(), at: 3.0 + Double(step) * 0.1)
        }
        XCTAssertEqual(coach.shown.issue, .lower, "still the old advice 0.6 s after the picture became right")
        XCTAssertGreaterThan(FramingCoach.readySettleSeconds, FramingCoach.settleSeconds)
        feed(&coach, reading(), from: 4.0, seconds: 1)
        XCTAssertTrue(coach.shown.isReady, "and ready once it has held")
    }

    func testLeavingReadyIsImmediate() {
        var coach = FramingCoach(angle: .side)
        feed(&coach, reading(), from: 0, seconds: 3)
        XCTAssertTrue(coach.shown.isReady)
        // Dark: after a handful of readings the average is dark, and the very next update says so — no waiting.
        var sawIssue = false
        for step in 0..<8 where !sawIssue {
            sawIssue = !coach.update(reading(brightness: 5), at: 3.0 + Double(step) * 0.1).isReady
        }
        XCTAssertTrue(sawIssue)
    }

    func testSmoothingSettlesOnASteadyReading() {
        var coach = FramingCoach(angle: .above)
        feed(&coach, reading(pitch: 80, brightness: 100), from: 0, seconds: 5)
        XCTAssertEqual(coach.smoothed.pitchDegrees ?? 0, 80, accuracy: 0.5)
        XCTAssertEqual(coach.smoothed.brightness ?? 0, 100, accuracy: 0.5)
        XCTAssertEqual(coach.smoothed.motion, 0, "motion is a moment, not an average")
    }

    func testAMissingNumberKeepsTheLastOne() {
        var coach = FramingCoach(angle: .side)
        coach.update(reading(pitch: 20), at: 0)
        coach.update(FramingReading(brightness: 110), at: 0.1)
        XCTAssertEqual(coach.smoothed.pitchDegrees ?? 0, 20, accuracy: 0.001)
    }
}

final class FrameAnalysisTests: XCTestCase {
    func testAFlatGreyPictureIsAsBrightAsItIsAndHasNothingSharp() throws {
        let measured = try XCTUnwrap(FrameAnalysis.measure(luma: [UInt8](repeating: 128, count: 40 * 30), width: 40, height: 30))
        XCTAssertEqual(measured.brightness, 128, accuracy: 0.001)
        XCTAssertEqual(measured.sharpness, 0, accuracy: 0.001)
    }

    func testAnEdgyPictureIsSharp() throws {
        var pixels = [UInt8](repeating: 0, count: 40 * 30)
        for y in 0..<30 { for x in 0..<40 where (x + y) % 2 == 0 { pixels[y * 40 + x] = 255 } }
        let measured = try XCTUnwrap(FrameAnalysis.measure(luma: pixels, width: 40, height: 30))
        XCTAssertGreaterThan(measured.sharpness, 10_000)
        XCTAssertEqual(measured.brightness, 127.5, accuracy: 2)
    }

    func testTheRowPaddingOfACameraBufferIsIgnored() throws {
        // 6 × 4 pixels of 100, each row padded to 8 bytes with 255s that must not count.
        var bytes = [UInt8](repeating: 255, count: 8 * 4)
        for y in 0..<4 { for x in 0..<6 { bytes[y * 8 + x] = 100 } }
        let measured = try XCTUnwrap(FrameAnalysis.measure(luma: bytes, width: 6, height: 4, bytesPerRow: 8))
        XCTAssertEqual(measured.brightness, 100, accuracy: 0.001)
        XCTAssertEqual(measured.sharpness, 0, accuracy: 0.001)
    }

    func testABigPictureIsShrunkByAveragingSoFineGrainIsNotMistakenForSharpness() throws {
        // One-pixel checkerboard at 1024 × 768: shrunk by averaging it is flat grey; read as it is, it would be "razor sharp".
        var pixels = [UInt8](repeating: 0, count: 1024 * 768)
        for y in 0..<768 { for x in 0..<1024 where (x + y) % 2 == 0 { pixels[y * 1024 + x] = 255 } }
        let measured = try XCTUnwrap(FrameAnalysis.measure(luma: pixels, width: 1024, height: 768))
        XCTAssertEqual(measured.brightness, 127.5, accuracy: 1)
        XCTAssertLessThan(measured.sharpness, 5)
    }

    func testAPictureTooSmallToMeasureGivesNothing() {
        XCTAssertNil(FrameAnalysis.measure(luma: [1, 2, 3, 4], width: 2, height: 2))
        XCTAssertNil(FrameAnalysis.measure(luma: [UInt8](repeating: 0, count: 10), width: 10, height: 10, bytesPerRow: 10))
        XCTAssertNil(FrameAnalysis.measure(luma: [UInt8](repeating: 0, count: 10), width: 5, height: 5, bytesPerRow: 2))
    }
}

/// A camera that does what the test tells it to.
private final class FakeCameraBackend: CameraBackend {
    var preview: CameraPreviewSource { .still(UIImage()) }
    var onReading: ((FramingReading) -> Void)?
    var onFailure: ((String) -> Void)?
    private(set) var started = 0
    private(set) var stopped = 0
    private(set) var captures = 0
    /// What the next capture hands back; nil is a photo that couldn't be taken.
    var photo: CapturedPhoto? = CapturedPhoto(image: UIImage(), pose: nil)

    func start() { started += 1 }
    func stop() { stopped += 1 }
    func capture(_ completion: @escaping (CapturedPhoto?) -> Void) {
        captures += 1
        completion(photo)
    }
}

@MainActor
final class GuidedCameraModelTests: XCTestCase {
    private var clock = 0.0

    private func model(_ backend: FakeCameraBackend, angle: PhotoAngle = .side, startupSeconds: Double = 6) -> GuidedCameraModel {
        clock = 0
        return GuidedCameraModel(angle: angle, backend: backend, startupSeconds: startupSeconds, now: { self.clock })
    }

    private let steady = FramingReading(pitchDegrees: 14, rollDegrees: 1, brightness: 110, sharpness: 400, motion: 0)

    func testItStartsTheCameraAndWaitsForTheFirstPicture() {
        let backend = FakeCameraBackend()
        let camera = model(backend)
        camera.start()
        XCTAssertEqual(backend.started, 1)
        XCTAssertEqual(camera.phase, .starting)
        XCTAssertEqual(camera.advice.issue, .notReady)
        camera.stop()
        XCTAssertEqual(backend.stopped, 1)
    }

    func testTheFirstReadingWithALightLevelStartsItRunning() {
        let backend = FakeCameraBackend()
        let camera = model(backend)
        camera.start()
        camera.receive(FramingReading(pitchDegrees: 14, rollDegrees: 0))      // motion only: no picture yet
        XCTAssertEqual(camera.phase, .starting)
        camera.receive(steady)
        XCTAssertEqual(camera.phase, .running)
        camera.stop()
    }

    func testAnAdviceFollowsTheReadingsAndTheLevelFollowsTheSmoothedRoll() {
        let backend = FakeCameraBackend()
        let camera = model(backend)
        camera.start()
        camera.receive(FramingReading(pitchDegrees: 60, rollDegrees: 0, brightness: 110, sharpness: 400, motion: 0))
        XCTAssertEqual(camera.advice.issue, .lower)
        camera.receive(FramingReading(pitchDegrees: 60, rollDegrees: 10, brightness: 110, sharpness: 400, motion: 0))
        XCTAssertEqual(camera.tilt.rollDegrees ?? 0, 3, accuracy: 0.001, "0 then 10, a third of the way")
        XCTAssertEqual(camera.tilt.pitchDegrees ?? 0, 60, accuracy: 0.001)
        camera.stop()
    }

    func testStartingTwiceStartsTheCameraOnce() {
        let backend = FakeCameraBackend()
        let camera = model(backend)
        camera.start()
        camera.start()
        XCTAssertEqual(backend.started, 1)
        camera.stop()
        camera.start()
        XCTAssertEqual(backend.started, 2, "but after it has been stopped it can start again")
        camera.stop()
    }

    func testACameraThatGaveUpIsStartedAgainWhenTheAppComesBack() {
        let backend = FakeCameraBackend()
        let camera = model(backend)
        camera.start()
        camera.receive(steady)
        camera.restartIfFailed()
        XCTAssertEqual(backend.started, 1, "a working camera is left alone")
        XCTAssertEqual(camera.phase, .running)

        backend.onFailure?("The camera was taken over by something else, such as a call.")
        let failed = expectation(description: "failed")
        Task { @MainActor in
            while camera.phase == .running { try? await Task.sleep(nanoseconds: 10_000_000) }
            failed.fulfill()
        }
        wait(for: [failed], timeout: 2)
        XCTAssertEqual(camera.phase, .failed("The camera was taken over by something else, such as a call."))

        camera.restartIfFailed()
        XCTAssertEqual(backend.started, 2)
        XCTAssertEqual(camera.phase, .starting)
        camera.receive(steady)
        XCTAssertEqual(camera.phase, .running)
        camera.stop()
    }

    func testTheTiltOnScreenIsRoundedSoATremorDoesNotRedrawIt() {
        let backend = FakeCameraBackend()
        let camera = model(backend)
        camera.start()
        camera.receive(FramingReading(pitchDegrees: 14.2, rollDegrees: 1.1, brightness: 110, sharpness: 400, motion: 0))
        XCTAssertEqual(camera.tilt, GuidedCameraModel.Tilt(pitchDegrees: 14, rollDegrees: 1))
        var redraws = 0
        let watch = camera.$tilt.dropFirst().sink { _ in redraws += 1 }
        for wobble in [14.3, 14.1, 14.4, 14.2] {
            camera.receive(FramingReading(pitchDegrees: wobble, rollDegrees: 1.1, brightness: 110, sharpness: 400, motion: 0))
        }
        XCTAssertEqual(redraws, 0, "a tenth of a degree is not worth a redraw")
        withExtendedLifetime(watch) {}
        camera.stop()
    }

    func testACameraThatNeverAnswersIsGivenUpOn() async throws {
        let backend = FakeCameraBackend()
        let camera = model(backend, startupSeconds: 0.05)
        camera.start()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(camera.phase, .failed("The camera didn't start."))
        XCTAssertGreaterThanOrEqual(backend.stopped, 1, "and let go of")
    }

    func testACameraThatAnswersInTimeIsNotGivenUpOn() async throws {
        let backend = FakeCameraBackend()
        let camera = model(backend, startupSeconds: 0.15)
        camera.start()
        camera.receive(steady)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(camera.phase, .running)
        camera.stop()
    }

    func testAFailureFromTheCameraShowsItsMessage() async throws {
        let backend = FakeCameraBackend()
        let camera = model(backend)
        camera.start()
        backend.onFailure?("The camera stopped working.")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(camera.phase, .failed("The camera stopped working."))
        camera.receive(steady)
        XCTAssertEqual(camera.phase, .failed("The camera stopped working."), "later readings don't bring it back")
    }

    func testThePhotoOnlyTakesWhileTheCameraIsRunning() {
        let backend = FakeCameraBackend()
        let camera = model(backend)
        camera.start()
        var taken = 0
        camera.takePhoto { _ in taken += 1 }
        XCTAssertEqual(backend.captures, 0, "not before the first picture")
        camera.receive(steady)
        camera.takePhoto { _ in taken += 1 }
        XCTAssertEqual(backend.captures, 1)
        camera.stop()
    }

    func testAPhotoIsHandedOverEvenWhileTheAdviceIsNotReady() async throws {
        let backend = FakeCameraBackend()
        let camera = model(backend)
        camera.start()
        camera.receive(FramingReading(pitchDegrees: 70, rollDegrees: 20, brightness: 10, sharpness: 5, motion: 3))
        XCTAssertFalse(camera.advice.isReady)
        let handedOver = expectation(description: "photo")
        camera.takePhoto { _ in handedOver.fulfill() }
        await fulfillment(of: [handedOver], timeout: 2)
        camera.stop()
    }

    func testAPhotoThatCouldNotBeTakenIsAFailureNotASilence() async throws {
        let backend = FakeCameraBackend()
        backend.photo = nil
        let camera = model(backend)
        camera.start()
        camera.receive(steady)
        var handedOver = false
        camera.takePhoto { _ in handedOver = true }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(handedOver)
        XCTAssertEqual(camera.phase, .failed("The photo couldn't be taken."))
    }

    func testTheShutterCannotBePressedTwiceForOnePhoto() {
        let backend = FakeCameraBackend()
        let camera = model(backend)
        camera.start()
        camera.receive(steady)
        camera.takePhoto { _ in }
        camera.takePhoto { _ in }
        XCTAssertEqual(backend.captures, 1)
        camera.stop()
    }
}

final class CameraScreenChoiceTests: XCTestCase {
    func testTheGuideIsUsedUnlessSomethingSaysOtherwise() {
        XCTAssertEqual(CameraScreen.choice(prefersGuide: true, switchedToStandard: false, guideAvailable: true), .guided)
        XCTAssertEqual(CameraScreen.choice(prefersGuide: false, switchedToStandard: false, guideAvailable: true), .standard, "turned off in Settings")
        XCTAssertEqual(CameraScreen.choice(prefersGuide: true, switchedToStandard: true, guideAvailable: true), .standard, "switched over from the guide")
        XCTAssertEqual(CameraScreen.choice(prefersGuide: true, switchedToStandard: false, guideAvailable: false), .standard, "a device that can't run it")
    }
}
