//
//  CameraPose.swift
//  PokerChipApp
//
//  How a photo was taken, from the phone's own sensors: how far below the horizon
//  the camera looked, how far the picture is tilted, and the lens. The counting
//  service uses it to know how each chip is foreshortened in a photo taken from the
//  side. Only these three numbers are sent: the photo's other metadata (where, when,
//  which phone) is never read out or sent.
//
//  The numbers come from the accelerometer reading the camera stores in every
//  photo (Apple's maker note, item 8): a vector pointing the way gravity does, in
//  the phone's own axes. The camera looks out of the back, along -z. For a photo
//  stored as the sensor saw it (EXIF orientation 1), the picture's "down" is the
//  phone's -x axis and its "right" the -y axis; the other orientations turn those.
//

import Foundation
import ImageIO
import UIKit

struct CameraPose: Equatable {
    /// How far below the horizon the camera looks, in degrees (0 level, 90 straight down).
    let pitchDegrees: Double
    /// How far the picture is turned about the camera's axis, in degrees, measured on
    /// the upright picture that is sent. nil when the photo doesn't say which way up it is.
    let rollDegrees: Double?
    /// The lens, as a 35 mm-equivalent focal length in millimetres, when the photo says.
    let focal35mm: Double?

    /// - Parameters:
    ///   - gravity: the accelerometer reading, in g, in the phone's axes.
    ///   - orientation: the photo's EXIF orientation (1, 3, 6 or 8 are understood).
    init?(gravity: (x: Double, y: Double, z: Double), orientation: Int?, focal35mm: Double?) {
        let length = (gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z).squareRoot()
        // A phone at rest reads one g. Much more or less means it was being shaken: no pose.
        guard length > 0.7, length < 1.3 else { return nil }

        let down = Self.clamp(-gravity.z / length, -1, 1)
        pitchDegrees = asin(down) * 180 / .pi

        if let orientation, let axes = Self.axes(for: orientation) {
            let alongDown = gravity.x * axes.down.x + gravity.y * axes.down.y + gravity.z * axes.down.z
            let alongRight = gravity.x * axes.right.x + gravity.y * axes.right.y + gravity.z * axes.right.z
            rollDegrees = atan2(-alongRight, alongDown) * 180 / .pi
        } else {
            rollDegrees = nil
        }
        self.focal35mm = focal35mm.flatMap { $0 >= 8 && $0 <= 200 ? $0 : nil }
    }

    /// The directions, in the phone's axes, of the upright picture's "down" and "right".
    private static func axes(for orientation: Int) -> (down: (x: Double, y: Double, z: Double), right: (x: Double, y: Double, z: Double))? {
        switch orientation {
        case 1: return ((-1, 0, 0), (0, -1, 0))   // as the sensor saw it
        case 3: return ((1, 0, 0), (0, 1, 0))     // turned half way round
        case 6: return ((0, -1, 0), (1, 0, 0))    // a portrait photo, the usual one
        case 8: return ((0, 1, 0), (-1, 0, 0))    // a portrait photo, phone upside down
        default: return nil                       // mirrored: not something a camera writes
        }
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }

    // MARK: Reading it from a photo

    /// The pose in a photo file's metadata, or nil if it carries none.
    static func from(imageData: Data) -> CameraPose? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }
        return from(metadata: properties)
    }

    /// The pose in a metadata dictionary of the shape ImageIO and the camera hand out.
    static func from(metadata: [String: Any]) -> CameraPose? {
        guard let apple = metadata[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any],
              let raw = apple["8"] as? [Any], raw.count == 3 else { return nil }
        let numbers = raw.compactMap { number($0) }
        guard numbers.count == 3 else { return nil }

        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let focal = number(exif?[kCGImagePropertyExifFocalLenIn35mmFilm as String])
        let orientation = (metadata[kCGImagePropertyOrientation as String] as? Int)
            ?? (metadata[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue
        return CameraPose(gravity: (numbers[0], numbers[1], numbers[2]), orientation: orientation, focal35mm: focal)
    }

    /// The camera writes these as numbers or as strings, depending on the route they took.
    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}
