//
//  FrameAnalysis.swift
//  PokerChipApp
//
//  How bright and how sharp the camera's live picture is, measured the way
//  `PhotoQuality` measures a finished photo, so the advice before the shot and the
//  check after it agree. A few times a second the camera hands over the brightness
//  plane of a frame; it is shrunk to about 256 pixels on its long edge by averaging
//  blocks of pixels, which costs well under a millisecond.
//

import Foundation

enum FrameAnalysis {
    /// Mean brightness (0–255) and sharpness (variance of the Laplacian) of an 8-bit greyscale
    /// picture, `bytesPerRow` apart (a camera buffer's rows are padded). Nil if it is too small to measure.
    static func measure(
        plane: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int,
        longEdge: Int = PhotoQuality.analysisLongEdge
    ) -> (brightness: Double, sharpness: Double)? {
        guard width >= 3, height >= 3, bytesPerRow >= width else { return nil }

        // Average blocks of `step` × `step` pixels into one: a box filter, the cheap way to shrink.
        let step = max(1, max(width, height) / max(longEdge, 1))
        let smallWidth = width / step
        let smallHeight = height / step
        guard smallWidth >= 3, smallHeight >= 3 else { return nil }

        var small = [UInt8](repeating: 0, count: smallWidth * smallHeight)
        let area = step * step
        for y in 0..<smallHeight {
            for x in 0..<smallWidth {
                var sum = 0
                for dy in 0..<step {
                    let row = plane + (y * step + dy) * bytesPerRow + x * step
                    for dx in 0..<step { sum += Int(row[dx]) }
                }
                small[y * smallWidth + x] = UInt8(truncatingIfNeeded: sum / area)
            }
        }
        let measured = PhotoQuality.measure(luma: small, width: smallWidth, height: smallHeight)
        return (measured.brightness, measured.sharpness)
    }

    /// The same, for bytes in an array (what the tests use). The array must hold every row; if it doesn't, nothing is read.
    static func measure(luma: [UInt8], width: Int, height: Int, bytesPerRow: Int? = nil) -> (brightness: Double, sharpness: Double)? {
        let stride = bytesPerRow ?? width
        guard luma.count >= stride * height else { return nil }
        return luma.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return nil }
            return measure(plane: base, width: width, height: height, bytesPerRow: stride)
        }
    }
}
