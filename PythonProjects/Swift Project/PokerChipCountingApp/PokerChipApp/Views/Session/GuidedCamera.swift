//
//  GuidedCamera.swift
//  PokerChipApp
//
//  A camera that helps line up the shot. While it is open it reads how the phone is
//  tilted, how bright the picture is and how sharp, and says in a few words what to
//  change: hold it flatter, lower, straighter, steadier; add light (`FramingAdvisor`
//  does the thinking). It never stops the shutter, and the photo it takes carries
//  the tilt the phone had at that moment, which is what the side-view counter uses.
//
//  The system camera stays one tap away ("Standard camera"), is used whenever this
//  one can't start, and can be made the default in Settings. The real camera can only
//  be tried on a phone; everything else here is driven by a stand-in in the tests.
//

import AVFoundation
import CoreMotion
import SwiftUI
import UIKit
import os

/// A finished photo, and how the phone was held when it was taken.
struct CapturedPhoto {
    let image: UIImage
    let pose: CameraPose?
}

/// What fills the screen behind the guidance: the live camera, or (in UI tests) a still picture.
enum CameraPreviewSource {
    case live(AVCaptureSession)
    case still(UIImage)
}

/// What the guided camera needs from a camera, so the real one and the test stand-in are interchangeable.
protocol CameraBackend: AnyObject {
    var preview: CameraPreviewSource { get }
    /// Called on the main queue, about ten times a second, once the camera is running.
    var onReading: ((FramingReading) -> Void)? { get set }
    /// Called on the main queue if the camera can't run.
    var onFailure: ((String) -> Void)? { get set }
    func start()
    func stop()
    /// Takes the photo. The completion is called on the main queue, with nil if it couldn't be taken.
    func capture(_ completion: @escaping (CapturedPhoto?) -> Void)
}

enum GuidedCamera {
    /// Whether the guided camera can be offered at all: a back camera is present (or a test stand-in is).
    static var isAvailable: Bool {
        AppEnvironment.usesStubCamera || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    static func makeBackend(angle: PhotoAngle) -> CameraBackend {
        #if DEBUG
        if AppEnvironment.usesStubCamera { return StubCameraBackend(angle: angle) }
        #endif
        return LiveCameraBackend()
    }
}

// MARK: - The real camera

final class LiveCameraBackend: NSObject, CameraBackend {
    private static let log = Logger(subsystem: "Vanarp.PokerChipApp", category: "guided-camera")

    let session = AVCaptureSession()
    var preview: CameraPreviewSource { .live(session) }
    var onReading: ((FramingReading) -> Void)?
    var onFailure: ((String) -> Void)?

    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "Vanarp.PokerChipApp.camera.session")
    private let analysisQueue = DispatchQueue(label: "Vanarp.PokerChipApp.camera.analysis")
    private let motion = CMMotionManager()
    private var isConfigured = false

    // Measured on the analysis queue, read on the main queue.
    private let frameLock = NSLock()
    private var brightness: Double?
    private var sharpness: Double?
    private var lastFrameTime = -1.0

    // Main queue only.
    private var gravity: (x: Double, y: Double, z: Double)?
    private var rotationRate: Double?
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []

    // Photos being taken, held until the photo output has called back for each.
    private let inFlightLock = NSLock()
    private var inFlight: [Int64: PhotoDelegate] = [:]

    deinit {
        ticker?.invalidate()
        motion.stopDeviceMotionUpdates()
    }

    // MARK: Starting and stopping

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] _ in
            self?.fail("The camera stopped working.")
        })
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] note in
            // Being sent to the background is not a failure: the system gives the camera back when the app returns.
            if let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int,
               AVCaptureSession.InterruptionReason(rawValue: raw) == .videoDeviceNotAvailableInBackground { return }
            self?.fail("The camera was taken over by something else, such as a call.")
        })

        sessionQueue.async { [weak self] in
            guard let self, self.configureIfNeeded() else { return }
            if !self.session.isRunning { self.session.startRunning() }
        }
        DispatchQueue.main.async { [weak self] in self?.startMotion() }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        motion.stopDeviceMotionUpdates()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        sessionQueue.async { [weak self] in
            if self?.session.isRunning == true { self?.session.stopRunning() }
        }
    }

    private func fail(_ message: String) {
        Self.log.error("Guided camera could not run: \(message, privacy: .public)")
        DispatchQueue.main.async { [weak self] in self?.onFailure?(message) }
    }

    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(photoOutput) else {
            fail("The camera couldn't be started.")
            return false
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .balanced

        // Only the guidance reads these frames, and only their brightness plane: small, and not turned upright.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey as String: 640,
            kCVPixelBufferHeightKey as String: 480,
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        // A phone that can't give them still takes photos; it just has less to say.
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if let connection = photoOutput.connection(with: .video) { Self.makeUpright(connection) }
        isConfigured = true
        return true
    }

    /// The picture is always upright (portrait), like the screen.
    static func makeUpright(_ connection: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    // MARK: Readings

    private func startMotion() {
        guard ticker == nil else { return }
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.1
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                self.gravity = (data.gravity.x, data.gravity.y, data.gravity.z)
                let rate = data.rotationRate
                self.rotationRate = (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot()
            }
        }
        // One steady beat, whether or not the motion sensors answer: the light and the focus still count.
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.emit() }
    }

    private func emit() {
        frameLock.lock()
        let brightness = self.brightness, sharpness = self.sharpness
        frameLock.unlock()

        var reading = FramingReading(brightness: brightness, sharpness: sharpness)
        reading.motion = rotationRate
        if let pose = currentPose() {
            reading.pitchDegrees = pose.pitchDegrees
            reading.rollDegrees = pose.rollDegrees
        }
        onReading?(reading)
    }

    /// The tilt the phone has right now (held upright, as the picture is taken), for a photo whose own metadata doesn't carry it.
    private func currentPose() -> CameraPose? {
        gravity.flatMap { CameraPose(gravity: $0, orientation: 6, focal35mm: nil) }
    }

    // MARK: Taking the photo

    func capture(_ completion: @escaping (CapturedPhoto?) -> Void) {
        let fallback = currentPose()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            let id = settings.uniqueID
            let delegate = PhotoDelegate(fallbackPose: fallback) { [weak self] photo in
                self?.release(id)
                DispatchQueue.main.async { completion(photo) }
            }
            self.hold(delegate, as: id)
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func hold(_ delegate: PhotoDelegate, as id: Int64) {
        inFlightLock.lock()
        inFlight[id] = delegate
        inFlightLock.unlock()
    }

    private func release(_ id: Int64) {
        inFlightLock.lock()
        inFlight[id] = nil
        inFlightLock.unlock()
    }

    /// One per photo.
    private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
        private let fallbackPose: CameraPose?
        private let done: (CapturedPhoto?) -> Void
        private var result: CapturedPhoto?

        init(fallbackPose: CameraPose?, done: @escaping (CapturedPhoto?) -> Void) {
            self.fallbackPose = fallbackPose
            self.done = done
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
            // The photo's own record of the tilt is exact to the shutter; the sensors a moment before are the next best.
            result = CapturedPhoto(image: image, pose: CameraPose.from(imageData: data) ?? fallbackPose)
        }

        /// The last call for every photo, whether it worked or not.
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
            done(error == nil ? result : nil)
        }
    }
}

extension LiveCameraBackend: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // A few times a second is plenty, and keeps the phone cool.
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard time - lastFrameTime >= 0.2 || time < lastFrameTime, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameTime = time

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) > 0, let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
              let measured = FrameAnalysis.measure(
                plane: base.assumingMemoryBound(to: UInt8.self),
                width: CVPixelBufferGetWidthOfPlane(buffer, 0),
                height: CVPixelBufferGetHeightOfPlane(buffer, 0),
                bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
              ) else { return }
        frameLock.lock()
        brightness = measured.brightness
        sharpness = measured.sharpness
        frameLock.unlock()
    }
}

// MARK: - The test stand-in

#if DEBUG
/// For UI tests, which have no camera: a still picture, readings that move on one step at a time
/// (too dark, too steep, tilted, then fine) and a photo that is the sample.
final class StubCameraBackend: CameraBackend {
    var onReading: ((FramingReading) -> Void)?
    var onFailure: ((String) -> Void)?
    // Drawn once: the screen asks for its picture every time it redraws, and drawing it is slow.
    private let picture = UITestSamplePhoto.sideImage()
    var preview: CameraPreviewSource { .still(picture) }

    private let angle: PhotoAngle
    private var step = 0
    private var ticker: Timer?

    /// What the phone "sees" at each step, from the first to the last, for a photo from the side.
    static let sideSteps: [FramingReading] = [
        FramingReading(pitchDegrees: 15, rollDegrees: 0, brightness: 30, sharpness: 500, motion: 0),    // dark
        FramingReading(pitchDegrees: 55, rollDegrees: 0, brightness: 110, sharpness: 500, motion: 0),   // too steep
        FramingReading(pitchDegrees: 15, rollDegrees: 12, brightness: 110, sharpness: 500, motion: 0),  // tilted
        FramingReading(pitchDegrees: 15, rollDegrees: 1, brightness: 110, sharpness: 500, motion: 0),   // fine
    ]
    /// And from above.
    static let topSteps: [FramingReading] = [
        FramingReading(pitchDegrees: 40, rollDegrees: 0, brightness: 110, sharpness: 500, motion: 0),   // not flat
        FramingReading(pitchDegrees: 88, rollDegrees: 0, brightness: 110, sharpness: 500, motion: 0),   // fine
    ]

    init(angle: PhotoAngle) {
        self.angle = angle
    }

    private var steps: [FramingReading] { angle == .side ? Self.sideSteps : Self.topSteps }

    func advance() { step = min(step + 1, steps.count - 1) }

    func start() {
        // Five a second, not ten: a UI test polls the screen from outside, and on a slow machine a busier
        // stand-in leaves it less time to answer.
        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.onReading?(self.steps[self.step])
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    func capture(_ completion: @escaping (CapturedPhoto?) -> Void) {
        if angle == .side {
            completion(CapturedPhoto(image: picture, pose: UITestSamplePhoto.samplePose))
        } else {
            completion(CapturedPhoto(image: UITestSamplePhoto.image(), pose: nil))
        }
    }
}
#endif

// MARK: - The model

@MainActor
final class GuidedCameraModel: ObservableObject {
    enum Phase: Equatable {
        case starting
        case running
        case capturing
        case failed(String)
    }

    /// The tilt as the screen shows it: whole degrees for the number, half degrees for the level line.
    /// Coarser than the sensor on purpose, so a hand's tremor doesn't redraw the screen ten times a second.
    struct Tilt: Equatable {
        var pitchDegrees: Double?
        var rollDegrees: Double?
    }

    @Published private(set) var advice = FramingAdvice(issue: .notReady, message: "Getting the camera ready…")
    @Published private(set) var tilt = Tilt()
    @Published private(set) var phase: Phase = .starting

    let angle: PhotoAngle
    let backend: CameraBackend
    private var coach: FramingCoach
    private let now: () -> TimeInterval
    private let startupSeconds: Double
    private var startupWatch: Task<Void, Never>?
    private var isStarted = false

    /// - Parameter startupSeconds: how long to wait for the first picture before giving up on the camera.
    init(
        angle: PhotoAngle, backend: CameraBackend, startupSeconds: Double = 6,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    ) {
        self.angle = angle
        self.backend = backend
        self.startupSeconds = startupSeconds
        self.now = now
        coach = FramingCoach(angle: angle)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        backend.onReading = { [weak self] reading in
            Task { @MainActor in self?.receive(reading) }
        }
        backend.onFailure = { [weak self] message in
            Task { @MainActor in self?.fail(message) }
        }
        phase = .starting
        backend.start()
        startupWatch?.cancel()
        startupWatch = Task { [weak self, startupSeconds] in
            try? await Task.sleep(nanoseconds: UInt64(startupSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.phase == .starting else { return }
            self.fail("The camera didn't start.")
        }
    }

    func stop() {
        isStarted = false
        startupWatch?.cancel()
        backend.stop()
    }

    /// When the app comes back to the front: a camera that gave up while it was away (a call came in, the phone
    /// was locked) is started again. One that is working is left alone.
    func restartIfFailed() {
        guard case .failed = phase else { return }
        stop()
        start()
    }

    private func fail(_ message: String) {
        phase = .failed(message)
        backend.stop()
    }

    /// One reading from the camera and the motion sensors (about ten a second).
    func receive(_ new: FramingReading) {
        guard phase == .starting || phase == .running || phase == .capturing else { return }
        if new.brightness != nil, phase == .starting { phase = .running }

        // Assign only what changed: every assignment to a @Published property redraws the screen.
        let shown = coach.update(new, at: now())
        if shown != advice { advice = shown }
        let smoothed = coach.smoothed
        let display = Tilt(
            pitchDegrees: smoothed.pitchDegrees.map { $0.rounded() },
            rollDegrees: smoothed.rollDegrees.map { ($0 * 2).rounded() / 2 }
        )
        if display != tilt { tilt = display }
    }

    func takePhoto(_ done: @escaping @MainActor (CapturedPhoto) -> Void) {
        guard phase == .running else { return }
        phase = .capturing
        backend.capture { [weak self] photo in
            Task { @MainActor in
                guard let self else { return }
                if let photo {
                    done(photo)
                } else {
                    self.fail("The photo couldn't be taken.")
                }
            }
        }
    }
}

// MARK: - On screen

struct GuidedCameraView: View {
    let angle: PhotoAngle
    var onCapture: (UIImage, CameraPose?) -> Void
    /// Switches to the system's own camera.
    var onUseStandardCamera: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: GuidedCameraModel
    @State private var lastSpoken = ""
    @State private var holdsScreenAwake = false
    @State private var wasKeepingAwake = false

    init(
        angle: PhotoAngle,
        makeBackend: @escaping () -> CameraBackend,
        onCapture: @escaping (UIImage, CameraPose?) -> Void,
        onUseStandardCamera: @escaping () -> Void
    ) {
        self.angle = angle
        self.onCapture = onCapture
        self.onUseStandardCamera = onUseStandardCamera
        _model = StateObject(wrappedValue: GuidedCameraModel(angle: angle, backend: makeBackend()))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            preview
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: Spacing.md) {
                advicePill
                    .padding(.top, Spacing.md)
                // Where the chips should end up: whatever room the words and the buttons leave.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                    .frame(maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                #if DEBUG
                if model.backend is StubCameraBackend {
                    Button { (model.backend as? StubCameraBackend)?.advance() } label: {
                        Text("Next reading")
                            .font(.pokerFootnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(minWidth: Spacing.minTapTarget, minHeight: Spacing.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("camera.stub.next")
                }
                #endif
                if angle == .side { HorizonLevel(roll: model.tilt.rollDegrees) }
                if let pitch = model.tilt.pitchDegrees {
                    Text("Camera tilted \(Int(pitch))° down")
                        .font(.pokerFootnote.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black, radius: 3)
                        .accessibilityHidden(true)
                }
                controls
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, Spacing.lg)

            if case .failed(let message) = model.phase { failure(message) }
        }
        .preferredColorScheme(.dark)
        // A viewfinder can't hand half its screen to words: text grows with the person's setting up to the first
        // accessibility size and then stops, as in the system camera, which is one tap away for anyone who needs more.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera")
        .onAppear {
            // Lining up a shot takes a while; the screen shouldn't dim on the way (and goes back as it was).
            if !holdsScreenAwake {
                holdsScreenAwake = true
                wasKeepingAwake = UIApplication.shared.isIdleTimerDisabled
                UIApplication.shared.isIdleTimerDisabled = true
            }
            model.start()
        }
        .onDisappear {
            if holdsScreenAwake {
                holdsScreenAwake = false
                UIApplication.shared.isIdleTimerDisabled = wasKeepingAwake
            }
            model.stop()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.restartIfFailed() }
        }
        .onChange(of: model.advice) { advice in
            // Say a change aloud, once, for someone who can't see the picture; never a repeat.
            guard UIAccessibility.isVoiceOverRunning, advice.message != lastSpoken else { return }
            lastSpoken = advice.message
            UIAccessibility.post(notification: .announcement, argument: advice.message)
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var preview: some View {
        switch model.backend.preview {
        case .live(let session):
            LiveCameraPreview(session: session)
        case .still(let image):
            // Filled and cropped to the screen; a picture wider than the phone must not widen the layout above it.
            Color.clear
                .overlay(Image(uiImage: image).resizable().scaledToFill())
                .clipped()
        }
    }

    private var advicePill: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: model.advice.isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(model.advice.isReady ? Color.pokerPositive : Color.pokerGoldLight)
                .accessibilityHidden(true)
            Text(model.advice.message)
                .font(.pokerCallout)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.advice)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.advice.message)
        .accessibilityIdentifier("camera.advice")
    }

    /// Cancel, the shutter and the way to the standard camera, in one row (the text never grows past what fits).
    private var controls: some View {
        HStack(alignment: .center) {
            cancelButton
            Spacer()
            shutterButton
            Spacer()
            standardCameraButton
        }
    }

    private var cancelButton: some View {
        Button { dismiss() } label: {
            Text("Cancel")
                .font(.pokerHeadline)
                .foregroundStyle(.white)
                .frame(minWidth: 80, minHeight: Spacing.minTapTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("camera.cancel")
    }

    private var shutterButton: some View {
        Button {
            model.takePhoto { photo in
                Haptics.success()
                dismiss()
                onCapture(photo.image, photo.pose)
            }
        } label: {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 4).frame(width: 76, height: 76)
                Circle()
                    .fill(model.advice.isReady ? Color.white : Color.white.opacity(0.78))
                    .frame(width: 62, height: 62)
            }
            .frame(minWidth: 84, minHeight: 84)
            .contentShape(Circle())
        }
        .disabled(model.phase != .running)
        .opacity(model.phase == .running ? 1 : 0.5)
        .accessibilityLabel("Take photo")
        .accessibilityHint(model.advice.message)
        .accessibilityIdentifier("camera.shutter")
    }

    private var standardCameraButton: some View {
        Button { useStandardCamera() } label: {
            Text("Standard\ncamera")
                .font(.pokerFootnote)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white.opacity(0.9))
                .frame(minWidth: 80, minHeight: Spacing.minTapTarget, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Use the standard camera")
        .accessibilityIdentifier("camera.standard")
    }

    /// Lets this camera go before the system's starts, so the two never hold the lens at once.
    private func useStandardCamera() {
        model.stop()
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            onUseStandardCamera()
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.pokerGoldLight)
                .accessibilityHidden(true)
            Text(message)
                .font(.pokerHeadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("You can try again, or use the standard camera instead.")
                .font(.pokerFootnote)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            PokerButton(title: "Try again", kind: .primary) { model.restartIfFailed() }
                .accessibilityIdentifier("camera.retry")
            PokerButton(title: "Use the standard camera", kind: .secondary) { useStandardCamera() }
                .accessibilityIdentifier("camera.fallback")
            PokerButton(title: "Cancel", kind: .quiet) { dismiss() }
                .accessibilityIdentifier("camera.failed.cancel")
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85).ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }
}

/// What opens when someone taps "Take photo": the guided camera, or the system's own when asked for
/// in Settings, when this device can't run the guide, or when the person switches over from it.
struct CameraScreen: View {
    enum Choice: Equatable {
        case guided
        case standard
    }

    /// The guided camera, unless the person has turned it off, has switched over from it, or this device can't run it.
    static func choice(prefersGuide: Bool, switchedToStandard: Bool, guideAvailable: Bool) -> Choice {
        prefersGuide && !switchedToStandard && guideAvailable ? .guided : .standard
    }

    let angle: PhotoAngle
    var onCapture: (UIImage, CameraPose?) -> Void

    @AppStorage(PrefKey.guidedCamera) private var guided = true
    @State private var usesStandardCamera = false

    var body: some View {
        if Self.choice(prefersGuide: guided, switchedToStandard: usesStandardCamera, guideAvailable: GuidedCamera.isAvailable) == .guided {
            GuidedCameraView(
                angle: angle,
                makeBackend: { GuidedCamera.makeBackend(angle: angle) },
                onCapture: onCapture,
                onUseStandardCamera: { usesStandardCamera = true }
            )
        } else {
            CameraPicker(angle: angle, onCapture: onCapture)
                .ignoresSafeArea()
        }
    }
}

/// The horizon as the camera sees it, against a fixed level line: when they lie on top of each other the phone is straight.
private struct HorizonLevel: View {
    let roll: Double?

    private var isLevel: Bool { abs(roll ?? 0) <= FramingAdvisor.levelRoll }

    var body: some View {
        ZStack {
            Capsule().fill(Color.white.opacity(0.45)).frame(width: 120, height: 2)
            Capsule()
                .fill(isLevel ? Color.pokerPositive : Color.pokerGoldLight)
                .frame(width: 120, height: 4)
                // Turned the way the horizon is turned in the picture: the right end lower for a positive roll.
                .rotationEffect(.degrees(roll ?? 0))
        }
        .frame(height: 44)
        .shadow(color: .black.opacity(0.6), radius: 2)
        .accessibilityHidden(true)
        .accessibilityIdentifier("camera.level")
    }
}

/// The live picture from the camera.
private struct LiveCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer?.session = session
        view.previewLayer?.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if let connection = view.previewLayer?.connection { LiveCameraBackend.makeUpright(connection) }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    }
}
