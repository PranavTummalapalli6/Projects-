//
//  ChipPhoto.swift
//  PokerChipApp
//
//  A counted photo, as the person sees it: the picture with a circle on every
//  chip the counting service found. Each circle can be recoloured, removed, or
//  added to, and the cash-out counts move with it. The photo lives in memory
//  only — it is never written to the phone.
//

import UIKit

/// A chip circled on a photo. Position and size are fractions of the photo's
/// width (y as well — a circle stays round at any size the photo is shown).
struct ChipMark: Identifiable, Hashable {
    let id: UUID
    var x: Double
    var y: Double
    var r: Double
    var color: String

    init(id: UUID = UUID(), x: Double, y: Double, r: Double, color: String) {
        self.id = id
        self.x = x
        self.y = y
        self.r = r
        self.color = color
    }

    init(_ detection: ChipDetection) {
        self.init(x: detection.x, y: detection.y, r: detection.r, color: detection.color)
    }
}

/// How the chips were photographed: laid out flat and shot from directly above, or
/// stood in piles and shot from the side or a low angle.
enum PhotoAngle: String, CaseIterable, Identifiable {
    case above
    case side

    var id: String { rawValue }
    var title: String { self == .above ? "From above" : "From the side" }
    /// What the counting service calls it.
    var serviceName: String { self == .above ? "top" : "side" }
}

/// A pile of chips marked on a photo taken from the side. Position and size are
/// fractions of the photo's width, as for `ChipMark`; `angle` is how far a box
/// there is turned, in degrees, positive clockwise (the screen's own direction).
struct StackMark: Identifiable, Hashable {
    /// The most chips one pile can be set to by hand.
    static let largest = 99

    let id: UUID
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    var angle: Double
    var color: String
    var count: Int
    /// What the counting service made of it: "low" or "medium". Nil for a pile added by hand.
    var confidence: String?

    init(id: UUID = UUID(), x: Double, y: Double, w: Double, h: Double, angle: Double = 0, color: String, count: Int, confidence: String? = nil) {
        self.id = id
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.angle = angle
        self.color = color
        self.count = count
        self.confidence = confidence
    }

    init(_ detection: StackDetection) {
        // The service turns boxes the way OpenCV does; the screen the other way.
        self.init(
            x: detection.x, y: detection.y, w: detection.w, h: detection.h, angle: -detection.angle,
            color: detection.color, count: max(1, detection.count), confidence: detection.confidence
        )
    }
}

struct PhotoCapture: Identifiable {
    let id: UUID
    let image: UIImage
    var marks: [ChipMark]
    var stacks: [StackMark]
    let angle: PhotoAngle

    init(id: UUID = UUID(), image: UIImage, marks: [ChipMark], stacks: [StackMark] = [], angle: PhotoAngle = .above) {
        self.id = id
        self.image = image
        self.marks = marks
        self.stacks = stacks
        self.angle = angle
    }

    /// Height over width.
    var aspectRatio: CGFloat {
        image.size.width > 0 ? image.size.height / image.size.width : 0.75
    }

    /// Nothing was found on this photo, so there is nothing to check.
    var isEmpty: Bool { marks.isEmpty && stacks.isEmpty }

    /// Chips counted on this photo, by colour: a circle is one chip, a pile is however many it holds.
    var tally: [String: Int] {
        var tally = marks.reduce(into: [String: Int]()) { $0[$1.color, default: 0] += 1 }
        for stack in stacks { tally[stack.color, default: 0] += stack.count }
        return tally
    }

    /// Chips counted on this photo.
    var chipCount: Int { tally.values.reduce(0, +) }

    /// The size a hand-added pile is drawn at: what the others in this photo look like.
    var typicalStackSize: (width: Double, height: Double) {
        guard !stacks.isEmpty else { return (0.14, 0.1) }
        let widths = stacks.map(\.w).sorted(), heights = stacks.map(\.h).sorted()
        return (widths[widths.count / 2], heights[heights.count / 2])
    }

    /// The size a hand-added chip is drawn at: what the others in this photo look like.
    var typicalRadius: Double {
        let radii = marks.map(\.r).sorted()
        guard !radii.isEmpty else { return 0.035 }
        return radii[radii.count / 2]
    }
}
