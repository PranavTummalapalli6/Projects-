//
//  UITestStubs.swift
//  PokerChipApp
//
//  Canned backend responses for `-UITestMode`, so UI tests drive the real app
//  deterministically with no Firebase and no network. Debug builds only —
//  none of this ships in Release.
//

#if DEBUG
import Foundation
import UIKit

extension ChipVisionAPIClient {
    static var uiTestStub: ChipVisionAPIClient {
        ChipVisionAPIClient(
            transport: { request in UITestStubs.respond(to: request) },
            baseURL: { URL(string: "https://stub.invalid")! },
            tokenProvider: { _ in "ui-test-token" },
            sleep: { _ in }
        )
    }
}

enum UITestStubs {
    static func respond(to request: URLRequest) -> (Data, URLResponse) {
        let url = request.url!
        let path = url.path
        let method = request.httpMethod ?? "GET"

        let status: Int
        let body: [String: Any]

        switch (method, path) {
        case ("POST", let p) where p.hasSuffix("/photo"):
            status = 200
            if request.httpBody?.range(of: Data("name=\"view\"\r\n\r\nside".utf8)) != nil {
                body = [
                    "counts": UITestSamplePhoto.sideTally,
                    "confidence": "low",
                    "photoUrl": "",
                    "detections": [Any](),
                    "view": "side",
                    "stacks": UITestSamplePhoto.sidePiles.map { pile -> [String: Any] in
                        let box = UITestSamplePhoto.sideBox(for: pile)
                        return ["x": box.x, "y": box.y, "w": box.w, "h": box.h, "angle": 0.0, "color": pile.color, "count": pile.count, "confidence": "low"]
                    },
                ]
            } else {
                body = [
                    "counts": ["White": 10, "Red": 7, "Blue": 5, "Green": 3, "Black": 2],
                    "confidence": "high",
                    "photoUrl": "",
                    "detections": UITestSamplePhoto.chips.map { chip -> [String: Any] in
                        ["x": chip.x, "y": chip.y, "r": UITestSamplePhoto.radius, "color": chip.color]
                    },
                ]
            }
        case ("POST", let p) where p.hasSuffix("/complete"):
            status = 200
            body = completeResult(for: request)
        case ("GET", "/v1/sessions/weekly-summary"):
            status = 200
            body = weeklySummary()
        case ("PUT", let p) where p.hasPrefix("/v1/nights/"):
            status = 200
            body = putNightResult(for: request)
        case ("GET", "/v1/nights"):
            status = 200
            body = ["nights": [Any](), "cursor": NSNull(), "hasMore": false]
        case ("POST", "/v1/nights/import-legacy"):
            status = 200
            body = ["imported": 0]
        case ("GET", "/healthz"):
            status = 200
            body = ["status": "ok"]
        case ("DELETE", "/v1/account"):
            return (Data(), response(url, 204))
        default:
            status = 404
            body = ["detail": "No stub for \(method) \(path)"]
        }

        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return (data, response(url, status))
    }

    private static func response(_ url: URL, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    /// Mirrors the backend: result computed in whole cents.
    private static func completeResult(for request: URLRequest) -> [String: Any] {
        guard
            let data = request.httpBody,
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let buyIn = payload["buyIn"] as? Double,
            let denominations = payload["denominations"] as? [String: Double],
            let counts = payload["finalCounts"] as? [String: Int]
        else {
            return ["profitLoss": 0.0, "profitLossCents": 0, "photoUrl": ""]
        }
        let ending = denominations.reduce(0) { $0 + (counts[$1.key] ?? 0) * Money.cents($1.value) }
        let profit = ending - Money.cents(buyIn)
        return ["profitLoss": Double(profit) / 100, "profitLossCents": profit, "photoUrl": ""]
    }

    /// The server keeps what it is sent (there is only ever one device here).
    private static func putNightResult(for request: URLRequest) -> [String: Any] {
        let night = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [String: Any]()
        return ["night": night, "applied": true, "serverUpdatedAt": "2026-01-01T00:00:00.000001+00:00"]
    }

    private static func weeklySummary() -> [String: Any] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let seconds = [0, 5400, 0, 7200, 3600, 0, 3600]
        let days: [[String: Any]] = (0..<7).map { index in
            let date = calendar.date(byAdding: .day, value: index - 6, to: Date())!
            return ["date": formatter.string(from: date), "seconds": seconds[index]]
        }
        return ["totalSeconds": seconds.reduce(0, +), "days": days]
    }
}

/// A picture of 27 chips laid out on a grid, and where each one is — what the
/// stubbed counting service "finds" in any photo, so a UI test can take a photo
/// (the camera and library can't be driven) and check the circles on it.
enum UITestSamplePhoto {
    struct Chip {
        let x: Double
        let y: Double
        let color: String
    }

    /// Radius as a fraction of the photo's width.
    static let radius = 0.04

    /// 10 White, 7 Red, 5 Blue, 3 Green and 2 Black, in rows of eight.
    static let chips: [Chip] = {
        let colors = Array(repeating: "White", count: 10) + Array(repeating: "Red", count: 7)
            + Array(repeating: "Blue", count: 5) + Array(repeating: "Green", count: 3) + Array(repeating: "Black", count: 2)
        return colors.enumerated().map { index, color in
            Chip(x: 0.09 + 0.116 * Double(index % 8), y: 0.12 + 0.12 * Double(index / 8), color: color)
        }
    }()

    // MARK: Piles seen from the side

    struct Pile {
        let color: String
        let count: Int
        /// Where it stands, as a fraction of the photo's width.
        let x: Double
    }

    /// What the stubbed counting service "finds" in a photo taken from the side: five piles in a row.
    static let sidePiles: [Pile] = [
        Pile(color: "White", count: 4, x: 0.14), Pile(color: "Red", count: 3, x: 0.32), Pile(color: "Blue", count: 2, x: 0.50),
        Pile(color: "Green", count: 5, x: 0.68), Pile(color: "Black", count: 1, x: 0.86),
    ]
    static var sideTally: [String: Int] { Dictionary(uniqueKeysWithValues: sidePiles.map { ($0.color, $0.count) }) }

    private static let pileWidth = 0.13
    private static let chipThickness = 0.011
    private static let capHeight = 0.035
    private static let pileBase = 0.5

    /// The camera pose the sample side photo "was taken" with: 18° down, a little tilted.
    static let samplePose = CameraPose(gravity: (-0.95, 0.05, -0.31), orientation: 1, focal35mm: 24)

    /// The box round a pile, as the service would send it (centre and size, fractions of the width).
    static func sideBox(for pile: Pile) -> (x: Double, y: Double, w: Double, h: Double) {
        let height = Double(pile.count) * chipThickness + capHeight
        return (pile.x, pileBase - height / 2 + 0.005, pileWidth + 0.02, height + 0.02)
    }

    /// A picture of the piles: stacks of chips standing on a dark table.
    static func sideImage(width: CGFloat = 1200, height: CGFloat = 900) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let cg = context.cgContext
            UIColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: (pileBase + 0.02) * width, width: width, height: height))
            // A cutting mat's grid: the check on the phone wants edges to measure, as a real table has grain.
            UIColor(white: 0.34, alpha: 1).setFill()
            var line: CGFloat = 0
            while line < width {
                cg.fill(CGRect(x: line, y: 0, width: 5, height: height))
                line += 56
            }
            line = 0
            while line < height {
                cg.fill(CGRect(x: 0, y: line, width: width, height: 5))
                line += 56
            }
            for pile in sidePiles {
                let chipWidth = pileWidth * width
                let thickness = chipThickness * width
                let left = pile.x * width - chipWidth / 2
                for chip in 0..<pile.count {
                    let top = (pileBase * width) - CGFloat(chip + 1) * thickness
                    let wall = CGRect(x: left, y: top, width: chipWidth, height: thickness)
                    UIColor(ChipPalette.rim(pile.color)).setFill()
                    cg.fill(wall)
                    UIColor(ChipPalette.spot(pile.color)).setFill()
                    for tab in 0..<3 {
                        cg.fill(CGRect(x: left + chipWidth * (0.14 + 0.30 * CGFloat(tab)), y: top, width: chipWidth * 0.14, height: thickness))
                    }
                    UIColor.black.withAlphaComponent(0.55).setFill()
                    cg.fill(CGRect(x: left, y: top + thickness - 2, width: chipWidth, height: 2))
                }
                let capTop = (pileBase * width) - CGFloat(pile.count) * thickness - capHeight * width / 2
                UIColor(ChipPalette.fill(pile.color)).setFill()
                cg.fillEllipse(in: CGRect(x: left, y: capTop, width: chipWidth, height: capHeight * width))
            }
        }
    }

    /// A flat grey picture: nothing sharp in it, so the check on the phone holds it back.
    static func blurryImage(width: CGFloat = 800, height: CGFloat = 600) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor(white: 0.5, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    static func image(width: CGFloat = 1200, height: CGFloat = 900) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor(red: 0.22, green: 0.20, blue: 0.18, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            for chip in chips {
                let diameter = CGFloat(radius * 2) * width
                let rect = CGRect(x: CGFloat(chip.x) * width - diameter / 2, y: CGFloat(chip.y) * width - diameter / 2, width: diameter, height: diameter)
                UIColor(ChipPalette.fill(chip.color)).setFill()
                context.cgContext.fillEllipse(in: rect)
                UIColor(ChipPalette.spot(chip.color)).setStroke()
                context.cgContext.setLineWidth(5)
                context.cgContext.strokeEllipse(in: rect.insetBy(dx: 5, dy: 5))
                UIColor(ChipPalette.rim(chip.color)).setStroke()
                context.cgContext.setLineWidth(3)
                context.cgContext.strokeEllipse(in: rect)
            }
        }
    }
}
#endif
