//
//  PhotoQuality.swift
//  PokerChipApp
//
//  A quick look at a photo before it is sent: is it sharp enough, lit well enough,
//  and big enough for chips to be told apart? Done on the phone in a few
//  milliseconds so that a bad photo is retaken at the table, not discovered after
//  a slow round trip. The checks only ever suggest a retake — the person can use
//  the photo anyway.
//
//  Sharpness is the variance of the Laplacian of a 256-pixel greyscale copy.
//  Thresholds were set against the nine sample photos in test_photos: sharp
//  ones score 1,000–2,000 and the same photos blurred by 16 pixels (at 12 MP)
//  score 55–110.
//

import CoreGraphics
import UIKit

enum PhotoQuality {
    enum Issue: Equatable {
        case blurry
        case tooDark
        case tooBright
        case lowResolution

        /// What to tell the person, ending with what to do about it.
        var message: String { message(for: .above) }

        func message(for angle: PhotoAngle) -> String {
            switch self {
            case .blurry:
                return angle == .side
                    ? "This photo looks blurry. Hold the phone steady, low and level with the piles, and try again for a better count."
                    : "This photo looks blurry. Hold the phone steady, directly above the chips, and try again for a better count."
            case .tooDark: return "This photo is quite dark, and dark chips will be hard to tell apart. Move closer to a light and try again."
            case .tooBright: return "This photo looks washed out, and glare hides chip colours. Move away from direct light and try again."
            case .lowResolution: return "This photo is small, so chips may be hard to tell apart. A larger photo will count better."
            }
        }
    }

    struct Report: Equatable {
        let sharpness: Double
        let brightness: Double
        let pixelWidth: Int
        let pixelHeight: Int
        /// What is wrong, most important first; empty when the photo looks fine.
        let issues: [Issue]

        var isGood: Bool { issues.isEmpty }
    }

    /// Long edge of the greyscale copy that is measured.
    static let analysisLongEdge = 256
    /// Below this variance of the Laplacian a photo is called blurry.
    static let minimumSharpness = 250.0
    /// Mean brightness (0–255) outside this range is called too dark / too bright.
    static let darkestBrightness = 35.0
    static let brightestBrightness = 225.0
    /// The long edge, in pixels, below which a photo is called small.
    static let minimumLongEdge = 600

    /// nil when the image has no pixels to look at (then it is simply used).
    static func assess(_ image: UIImage) -> Report? {
        guard let cgImage = image.cgImage else { return nil }
        return assess(cgImage)
    }

    static func assess(_ cgImage: CGImage) -> Report {
        let width = cgImage.width, height = cgImage.height
        let scale = min(1, Double(analysisLongEdge) / Double(max(width, height, 1)))
        let smallWidth = max(3, Int((Double(width) * scale).rounded()))
        let smallHeight = max(3, Int((Double(height) * scale).rounded()))

        var luma = [UInt8](repeating: 0, count: smallWidth * smallHeight)
        luma.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: smallWidth,
                height: smallHeight,
                bitsPerComponent: 8,
                bytesPerRow: smallWidth,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        }

        let measured = measure(luma: luma, width: smallWidth, height: smallHeight)
        var issues: [Issue] = []
        if measured.brightness < darkestBrightness { issues.append(.tooDark) }
        if measured.brightness > brightestBrightness { issues.append(.tooBright) }
        // A dark or washed-out photo has little contrast to be sharp with, so the
        // lighting is what to fix first.
        if measured.sharpness < minimumSharpness && issues.isEmpty { issues.append(.blurry) }
        if max(width, height) < minimumLongEdge { issues.append(.lowResolution) }

        return Report(sharpness: measured.sharpness, brightness: measured.brightness, pixelWidth: width, pixelHeight: height, issues: issues)
    }

    /// Mean brightness and the variance of the 4-neighbour Laplacian of an 8-bit greyscale picture.
    static func measure(luma: [UInt8], width: Int, height: Int) -> (sharpness: Double, brightness: Double) {
        guard width >= 3, height >= 3, luma.count >= width * height else { return (0, 0) }

        var total = 0.0
        for value in luma[0..<(width * height)] { total += Double(value) }
        let brightness = total / Double(width * height)

        var sum = 0.0, sumOfSquares = 0.0, count = 0.0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                let laplacian = Int(luma[index - width]) + Int(luma[index + width]) + Int(luma[index - 1]) + Int(luma[index + 1]) - 4 * Int(luma[index])
                sum += Double(laplacian)
                sumOfSquares += Double(laplacian * laplacian)
                count += 1
            }
        }
        let mean = sum / count
        return (sumOfSquares / count - mean * mean, brightness)
    }
}
