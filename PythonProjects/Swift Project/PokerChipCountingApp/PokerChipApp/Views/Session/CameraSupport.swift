//
//  CameraSupport.swift
//  PokerChipApp
//
//  Camera availability and permission, and the two ways a photo gets in: the
//  camera and the photo library. Neither writes the image anywhere — it goes to
//  the caller, held in memory for the upload, and is then discarded.
//

import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum CameraAccess {
    enum Status: Equatable {
        /// Camera present and allowed.
        case ready
        /// Camera present; the system will ask on first use.
        case needsPermission
        /// The person said no. Only Settings can change that.
        case denied
        /// Blocked by Screen Time / a device profile.
        case restricted
        /// No camera (Simulator, some iPads).
        case unavailable
    }

    static var status: Status {
        #if DEBUG
        // A UI test has no camera; the guided camera's stand-in needs the screen to believe there is one.
        if AppEnvironment.usesStubCamera { return .ready }
        #endif
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .ready
        case .notDetermined: return .needsPermission
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// What to tell someone when the camera can't be used, or nil if it can.
    static func explanation(for status: Status) -> String? {
        switch status {
        case .ready, .needsPermission:
            return nil
        case .denied:
            return "Camera access is turned off for Chip Counter. Turn it on in Settings, or choose a photo or count by hand."
        case .restricted:
            return "The camera is restricted on this device. Choose a photo or count by hand."
        case .unavailable:
            return "This device has no camera. Choose a photo or count by hand."
        }
    }
}

/// The system camera. Presented full-screen by the caller. Hands back the photo and,
/// when the camera says, how it was held (see `CameraPose`).
struct CameraPicker: UIViewControllerRepresentable {
    var angle: PhotoAngle = .above
    var onCapture: (UIImage, CameraPose?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        let guide = FramingGuideView(frame: picker.view.bounds, angle: angle)
        picker.cameraOverlayView = guide
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            let pose = (info[.mediaMetadata] as? [String: Any]).flatMap(CameraPose.from(metadata:))
            parent.dismiss()
            if let image { parent.onCapture(image, pose) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// A dashed frame and a line of advice laid over the camera, so the chips end up
/// inside the picture and photographed the way the counting reads them. It never
/// takes a touch.
final class FramingGuideView: UIView {
    private let frameLayer = CAShapeLayer()
    private let label = UILabel()

    /// What the line of advice says for how the chips are being photographed.
    static func advice(for angle: PhotoAngle) -> String {
        switch angle {
        case .above: return "Fit all the chips inside the frame, from directly above"
        case .side: return "Line the piles up inside the frame, a hand apart. Hold the phone low and level with them"
        }
    }

    init(frame: CGRect, angle: PhotoAngle = .above) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        frameLayer.fillColor = UIColor.clear.cgColor
        frameLayer.strokeColor = UIColor.white.withAlphaComponent(0.85).cgColor
        frameLayer.lineWidth = 2
        frameLayer.lineDashPattern = [10, 6]
        layer.addSublayer(frameLayer)

        label.text = Self.advice(for: angle)
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 2
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("FramingGuideView is only created in code")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The system's own bars sit above and below the picture.
        let area = bounds.inset(by: UIEdgeInsets(top: 120, left: 20, bottom: 170, right: 20))
        guard area.width > 0, area.height > 0 else { return }
        frameLayer.path = UIBezierPath(roundedRect: area, cornerRadius: 18).cgPath
        let labelSize = label.sizeThatFits(CGSize(width: area.width - 40, height: .greatestFiniteMagnitude))
        label.frame = CGRect(
            x: area.midX - (labelSize.width + 24) / 2,
            y: area.minY + 12,
            width: labelSize.width + 24,
            height: labelSize.height + 12
        )
    }
}

/// Lets the user hand over an existing photo instead of shooting a new one —
/// same image in, same callback, so it feeds the exact same upload/analysis
/// path as the camera. Uses PHPickerViewController (not UIImagePickerController's
/// .photoLibrary source): it runs out-of-process, so the app never touches the
/// photo library itself and needs no NSPhotoLibraryUsageDescription entry or
/// permission prompt. The photo file's own metadata is read for how the camera was
/// held (`CameraPose`); nothing else in it is.
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    var onPick: (UIImage, CameraPose?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: PhotoLibraryPicker
        init(_ parent: PhotoLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data, let image = UIImage(data: data) else { return }
                let pose = CameraPose.from(imageData: data)
                DispatchQueue.main.async { self.parent.onPick(image, pose) }
            }
        }
    }
}
