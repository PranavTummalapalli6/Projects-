//
//  FramingAdvisor.swift
//  PokerChipApp
//
//  What to tell someone who is lining up a photo of their chips: hold the phone
//  flatter, lower, straighter or steadier; add light. It is arithmetic on a few
//  numbers — how the phone is tilted, how bright and how sharp the picture is — so
//  every sentence can be tested without a camera. It only ever advises: the shutter
//  is always there, and a photo taken against the advice is still counted.
//
//  The tilt that suits each way of photographing is what the counting reads best:
//  from above, the camera looking straight down; from the side, looking out and a
//  little down (up to 30°), level, so each chip is a thin band and not a disc.
//

import Foundation

/// What the phone and the camera are reporting right now. Anything not yet known is nil.
struct FramingReading: Equatable {
    /// How far below the horizon the camera looks: 0 level, 90 straight down.
    var pitchDegrees: Double?
    /// How far the picture is turned, in degrees; positive means the horizon slopes down to the right.
    var rollDegrees: Double?
    /// Mean brightness of the preview, 0–255.
    var brightness: Double?
    /// How sharp the preview is (variance of its Laplacian, as `PhotoQuality` measures a photo).
    var sharpness: Double?
    /// How fast the phone is turning, in radians a second.
    var motion: Double?
}

enum FramingIssue: Equatable {
    case notReady
    case holdUpright
    case tooDark
    case tooBright
    case flatten
    case lower
    case tiltDown
    case straighten
    case holdStill
    case blurry
}

struct FramingAdvice: Equatable {
    /// What to fix first, or nil when the picture is ready to take.
    let issue: FramingIssue?
    let message: String

    var isReady: Bool { issue == nil }
}

enum FramingAdvisor {
    // MARK: What counts as good

    /// Held on its side or upside down: the side-view guide is built for an upright phone.
    static let uprightRoll = 35.0
    /// "Turned" is the angle between the phone's own up and the way gravity leans across its screen, so it
    /// means nothing as the camera nears straight down (the lean is a hair and its direction noise). Judged only below this.
    static let turnMeaningfulBelowPitch = 75.0
    /// From above: at least this far down (90 is straight down).
    static let flatEnoughPitch = 72.0
    /// From the side: no steeper than this, and no higher than this (a little up is fine).
    static let sideSteepestPitch = 30.0
    static let sideHighestPitch = -8.0
    /// From the side, the horizon is level to within this many degrees.
    static let levelRoll = 5.0
    /// The preview, as a mean brightness, is dark below this and washed out above that: the very limits the
    /// check on a finished photo uses, so the advice before the shot never contradicts the check after it.
    static let darkestBrightness = PhotoQuality.darkestBrightness
    static let brightestBrightness = PhotoQuality.brightestBrightness
    /// Turning faster than this (radians a second) is moving, not holding still.
    static let stillestMotion = 0.8
    /// A sharpness of the preview below this, while the phone is still, is a picture that won't focus. Set low on purpose: a wrong "it's soft" is worse than a missing one.
    static let minimumSharpness = 80.0

    static func advice(for reading: FramingReading, angle: PhotoAngle) -> FramingAdvice {
        // Light and focus come from the camera, tilt from the motion sensors; with neither there is
        // nothing to say yet. Without motion sensors the tilt advice is simply left out.
        guard reading.brightness != nil else {
            return FramingAdvice(issue: .notReady, message: "Getting the camera ready…")
        }

        // Circles don't mind a turned picture, so from above the phone may be held any way round. The
        // piles are measured against the horizon, so from the side it must be upright.
        if angle == .side, let roll = reading.rollDegrees, let pitch = reading.pitchDegrees,
           pitch < turnMeaningfulBelowPitch, abs(roll) > uprightRoll {
            return FramingAdvice(issue: .holdUpright, message: "Hold the phone upright, the way you would for any photo.")
        }
        if let brightness = reading.brightness {
            if brightness < darkestBrightness {
                return FramingAdvice(issue: .tooDark, message: "It's dark in here. Turn on a light, or move closer to one.")
            }
            if brightness > brightestBrightness {
                return FramingAdvice(issue: .tooBright, message: "Glare is washing the picture out. Move away from direct light.")
            }
        }

        if let pitch = reading.pitchDegrees {
            switch angle {
            case .above:
                if pitch < flatEnoughPitch {
                    return FramingAdvice(issue: .flatten, message: "Hold the phone flat above the chips, with the camera pointing straight down.")
                }
            case .side:
                if pitch > sideSteepestPitch {
                    return FramingAdvice(issue: .lower, message: "Lower the phone to the height of the piles, and look at them from the side.")
                }
                if pitch < sideHighestPitch {
                    return FramingAdvice(issue: .tiltDown, message: "Tilt the phone down a little so the piles are in the middle.")
                }
            }
        }
        if angle == .side, let roll = reading.rollDegrees, abs(roll) > levelRoll {
            return FramingAdvice(issue: .straighten, message: "Straighten the phone: the picture is tilted.")
        }

        let motion = reading.motion ?? 0
        if motion > stillestMotion {
            return FramingAdvice(issue: .holdStill, message: "Hold still…")
        }
        if let sharpness = reading.sharpness, sharpness < minimumSharpness {
            // Soft while the phone is still is a focus problem; soft while it is moving is just the movement.
            return motion > stillestMotion / 2
                ? FramingAdvice(issue: .holdStill, message: "Hold still…")
                : FramingAdvice(issue: .blurry, message: "The picture is soft. Hold still, and move back a little so the camera can focus.")
        }
        return FramingAdvice(issue: nil, message: "Looks good. Take the photo.")
    }
}

/// Smooths what the sensors say and keeps the advice from flickering: a reading is averaged with
/// the ones before it, and a change of advice must hold for a moment before it is shown.
struct FramingCoach {
    /// How much of each new reading goes into the average (1 would be no smoothing).
    static let smoothing = 0.3
    /// How long a different piece of advice has to hold before it replaces the one on show; being
    /// ready has to hold longer, so it doesn't flash as the phone swings through level.
    static let settleSeconds = 0.5
    static let readySettleSeconds = 0.9

    let angle: PhotoAngle
    private(set) var smoothed = FramingReading()
    private(set) var shown: FramingAdvice
    private var candidate: FramingAdvice?
    private var candidateSince: TimeInterval = 0

    init(angle: PhotoAngle) {
        self.angle = angle
        shown = FramingAdvice(issue: .notReady, message: "Getting the camera ready…")
    }

    /// Takes a new reading and returns the advice to show. `now` is any steadily increasing clock, in seconds.
    @discardableResult
    mutating func update(_ reading: FramingReading, at now: TimeInterval) -> FramingAdvice {
        smoothed = Self.blend(smoothed, with: reading)
        let latest = FramingAdvisor.advice(for: smoothed, angle: angle)

        if latest == shown {
            candidate = nil
            return shown
        }
        // Leaving "ready", or the start-up message, is at once: a picture that has just stopped being
        // right shouldn't say it is, and nobody should wait for the first piece of advice.
        if shown.isReady || shown.issue == .notReady {
            shown = latest
            candidate = nil
            return shown
        }
        // Anything else has to hold for a moment before it replaces what is on show.
        if candidate != latest {
            candidate = latest
            candidateSince = now
        }
        if now - candidateSince >= (latest.isReady ? Self.readySettleSeconds : Self.settleSeconds) {
            shown = latest
            candidate = nil
        }
        return shown
    }

    private static func blend(_ old: FramingReading, with new: FramingReading) -> FramingReading {
        func mix(_ a: Double?, _ b: Double?) -> Double? {
            guard let b else { return a }
            guard let a else { return b }
            return a + (b - a) * smoothing
        }
        return FramingReading(
            pitchDegrees: mix(old.pitchDegrees, new.pitchDegrees),
            rollDegrees: mix(old.rollDegrees, new.rollDegrees),
            brightness: mix(old.brightness, new.brightness),
            sharpness: mix(old.sharpness, new.sharpness),
            // Motion is a moment, not a trend: no averaging, so holding still is noticed at once.
            motion: new.motion ?? old.motion
        )
    }
}
