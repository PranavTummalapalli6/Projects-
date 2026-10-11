import PickleCore
import SwiftUI

/// Map/status semantics. Always rendered as icon + label (+ color), never color alone.
enum FacilityStatus: Equatable {
    case likelyAvailable, moderateWait, busy, unknown, surfaceIssue, accessRestricted, blackout, temporarilyClosed

    init(_ r: FacilityRecommendation) {
        switch r.eligibility.status {
        case .restricted: self = .accessRestricted
        case .unavailable:
            switch r.eligibility.issue {
            case .blackout: self = .blackout
            case .surface: self = .surfaceIssue
            default: self = .temporarilyClosed
            }
        case .eligible:
            if r.prediction.basis == .prior && !r.prediction.hasLiveData { self = .unknown; return }
            switch r.prediction.busyLevel {
            case .quiet: self = .likelyAvailable
            case .moderate: self = .moderateWait
            case .busy, .veryBusy: self = .busy
            }
        }
    }

    var label: String {
        switch self {
        case .likelyAvailable: "Likely available"
        case .moderateWait: "Moderate wait"
        case .busy: "Busy"
        case .unknown: "No recent info"
        case .surfaceIssue: "Surface issue"
        case .accessRestricted: "Access restricted"
        case .blackout: "Event — unavailable"
        case .temporarilyClosed: "Unavailable now"
        }
    }

    var symbol: String {
        switch self {
        case .likelyAvailable: "checkmark"
        case .moderateWait: "hourglass"
        case .busy: "person.3.fill"
        case .unknown: "questionmark"
        case .surfaceIssue: "drop.fill"
        case .accessRestricted: "lock.fill"
        case .blackout: "calendar.badge.exclamationmark"
        case .temporarilyClosed: "xmark"
        }
    }

    var color: Color {
        switch self {
        case .likelyAvailable: Theme.available
        case .moderateWait: Theme.moderate
        case .busy: Theme.busy
        case .unknown: Theme.unknown
        case .surfaceIssue: Theme.surfaceIssue
        case .accessRestricted: Theme.restricted
        case .blackout, .temporarilyClosed: Theme.unavailable
        }
    }

    var isPlayable: Bool { [.likelyAvailable, .moderateWait, .busy, .unknown].contains(self) }
}

enum Icons {
    static func access(_ a: AccessType) -> String {
        switch a {
        case .publicWalkOn: "figure.walk"
        case .publicReservation: "calendar.badge.clock"
        case .publicPermitRequired: "doc.text"
        case .residentOnly, .residentGuestAllowed: "house.fill"
        case .hoa: "house.and.flag.fill"
        case .membershipRequired: "person.crop.circle.badge.checkmark"
        case .dayPassAvailable: "ticket.fill"
        case .private: "lock.fill"
        case .schoolRestricted: "graduationcap.fill"
        case .unknown: "questionmark.circle"
        }
    }

    static func cost(_ c: CostFit) -> String {
        switch c {
        case .free: "gift"
        case .paid, .outsidePreference: "dollarsign.circle"
        case .membership: "person.crop.circle.badge.checkmark"
        case .unknown: "questionmark.circle"
        }
    }

    static func surface(_ s: SurfaceCondition) -> String {
        switch s {
        case .dry: "sun.max.fill"
        case .slightlyDamp: "drop"
        case .wet: "drop.fill"
        case .standingWater: "water.waves"
        case .debris: "leaf.fill"
        case .iceSnow: "snowflake"
        case .construction: "hammer.fill"
        case .unsafe: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    static func occupancy(_ s: OccupancyStatus) -> String {
        switch s {
        case .courtsOpen: "checkmark.circle.fill"
        case .mostlyFull: "circle.lefthalf.filled"
        case .allFull: "circle.fill"
        case .playersWaiting: "person.3.sequence.fill"
        case .unknown: "questionmark.circle"
        }
    }

    static func paddle(_ p: PaddleStackLevel) -> String {
        switch p {
        case .none: "checkmark.circle.fill"
        case .short: "square.stack"
        case .medium: "square.stack.3d.up"
        case .long: "square.stack.3d.up.fill"
        case .unknown: "questionmark.circle"
        }
    }

    static func culture(_ t: PlayCultureTag) -> String {
        switch t {
        case .openPlay: "person.3.fill"
        case .organizedRotation: "arrow.triangle.2.circlepath"
        case .challengeCourt: "trophy.fill"
        case .mostlyDoubles: "person.2.fill"
        case .singlesAvailable: "person.fill"
        case .beginnerFriendly: "hand.wave.fill"
        case .casual: "face.smiling"
        case .competitive: "flame.fill"
        case .mixed: "circle.grid.2x2.fill"
        case .unknown: "questionmark.circle"
        }
    }

    static func wind(_ w: WindCategory) -> String {
        switch w {
        case .calm: "leaf"
        case .breezy: "wind"
        case .windy, .veryWindy: "wind.circle.fill"
        }
    }

    static func color(for confidence: ConfidenceLevel) -> Color {
        switch confidence {
        case .high: Theme.available
        case .medium: Theme.moderate
        case .low: Theme.unknown
        }
    }
}
