//
//  ImagePreparation.swift
//  PokerChipApp
//
//  Gets a photo ready to send: upright, and no bigger than the backend needs.
//  A 12-megapixel photo is ~3 MB of JPEG; 1600 px on the long edge is plenty to
//  find and colour-match chips and keeps an upload on weak signal quick.
//

import UIKit

extension UIImage {
    /// Redraws the image upright (the camera stores rotation as metadata, which
    /// a re-encode would otherwise drop) and scales it down so its long edge is
    /// at most `maxLongEdge` points. Never scales up.
    func preparedForUpload(maxLongEdge: CGFloat = 1600) -> UIImage {
        let longEdge = max(size.width, size.height)
        let scale = longEdge > maxLongEdge ? maxLongEdge / longEdge : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        // Already upright and small enough: nothing to do.
        if scale == 1 && imageOrientation == .up { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1  // `target` is in pixels, not points
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
