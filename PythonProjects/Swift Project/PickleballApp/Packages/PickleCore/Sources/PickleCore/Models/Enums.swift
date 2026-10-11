import Foundation

/// String-backed enum that decodes unknown server values to a fallback instead of failing the
/// whole payload. The backend can add cases without breaking shipped clients.
public protocol ResilientEnum: RawRepresentable, Codable, CaseIterable, Hashable, Sendable where RawValue == String {
    static var fallback: Self { get }
}

public extension ResilientEnum {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }
}

public enum CourtType: String, ResilientEnum {
    case dedicatedPickleball = "dedicated_pickleball"
    case pickleballLinedTennis = "pickleball_lined_tennis"
    case convertibleTennis = "convertible_tennis"
    case multiUse = "multi_use"
    case mixedFacility = "mixed_facility"
    case unknown
    public static let fallback = CourtType.unknown

    public var displayName: String {
        switch self {
        case .dedicatedPickleball: "Dedicated pickleball"
        case .pickleballLinedTennis: "Tennis + pickleball lines"
        case .convertibleTennis: "Tennis, portable nets"
        case .multiUse: "Multi-use courts"
        case .mixedFacility: "Mixed dedicated + converted"
        case .unknown: "Court type unknown"
        }
    }
}

public enum IndoorOutdoor: String, ResilientEnum {
    case indoor, outdoor, both, unknown
    public static let fallback = IndoorOutdoor.unknown
    public var hasOutdoorCourts: Bool { self == .outdoor || self == .both || self == .unknown }
}

public enum AccessType: String, ResilientEnum {
    case publicWalkOn = "public_walk_on"
    case publicReservation = "public_reservation"
    case publicPermitRequired = "public_permit_required"
    case residentOnly = "resident_only"
    case residentGuestAllowed = "resident_guest_allowed"
    case hoa
    case membershipRequired = "membership_required"
    case dayPassAvailable = "day_pass_available"
    case `private`
    case schoolRestricted = "school_restricted"
    case unknown
    public static let fallback = AccessType.unknown

    public var displayName: String {
        switch self {
        case .publicWalkOn: "Public walk-on"
        case .publicReservation: "Public, reservation"
        case .publicPermitRequired: "Public, permit required"
        case .residentOnly: "Residents only"
        case .residentGuestAllowed: "Residents & guests"
        case .hoa: "HOA members"
        case .membershipRequired: "Members only"
        case .dayPassAvailable: "Day pass available"
        case .private: "Private"
        case .schoolRestricted: "School hours restricted"
        case .unknown: "Access unknown"
        }
    }

    /// Whether an ordinary visiting player can generally get on a court.
    public var isOpenToOrdinaryPlayers: Bool {
        switch self {
        case .publicWalkOn, .publicReservation, .publicPermitRequired, .dayPassAvailable, .unknown: true
        case .schoolRestricted: true // restricted only during school hours; handled by hours/rules
        case .residentOnly, .residentGuestAllowed, .hoa, .membershipRequired, .private: false
        }
    }
}

public enum AccessCostType: String, ResilientEnum {
    case free, paid
    case dayPass = "day_pass"
    case reservationFee = "reservation_fee"
    case membership, unknown
    public static let fallback = AccessCostType.unknown
    public var isFree: Bool { self == .free }
}

public enum CostPreference: String, ResilientEnum {
    case freeOnly = "free_only"
    case includePaid = "include_paid"
    case noPreference = "no_preference"
    public static let fallback = CostPreference.noPreference
}

public enum PlaySystem: String, ResilientEnum {
    case paddleStack = "paddle_stack"
    case rotationBoard = "rotation_board"
    case stayUntilFinished = "stay_until_finished"
    case reservationOnly = "reservation_only"
    case organizedOpenPlay = "organized_open_play"
    case unknown
    public static let fallback = PlaySystem.unknown
    public var isRotation: Bool { self == .paddleStack || self == .rotationBoard || self == .organizedOpenPlay }
}

public enum VerificationStatus: String, ResilientEnum {
    case pending
    case communityReported = "community_reported"
    case partiallyVerified = "partially_verified"
    case verified, rejected, closed
    public static let fallback = VerificationStatus.pending
}

public enum SkillBand: String, ResilientEnum, Comparable {
    case beginner
    case b20_25 = "2.0-2.5"
    case b25_30 = "2.5-3.0"
    case b30_35 = "3.0-3.5"
    case b35_40 = "3.5-4.0"
    case b40_45 = "4.0-4.5"
    case b45plus = "4.5+"
    case unknown
    public static let fallback = SkillBand.unknown

    /// Ordinal position on the skill ladder; nil for `.unknown`.
    public var ordinal: Int? {
        switch self {
        case .beginner: 0
        case .b20_25: 1
        case .b25_30: 2
        case .b30_35: 3
        case .b35_40: 4
        case .b40_45: 5
        case .b45plus: 6
        case .unknown: nil
        }
    }

    public static var ladder: [SkillBand] { allCases.filter { $0 != .unknown } }

    public static func from(ordinal: Int) -> SkillBand {
        ladder.first { $0.ordinal == min(max(ordinal, 0), 6) } ?? .unknown
    }

    public var displayName: String {
        switch self {
        case .beginner: "Beginner / learning"
        case .b20_25: "2.0–2.5"
        case .b25_30: "2.5–3.0"
        case .b30_35: "3.0–3.5"
        case .b35_40: "3.5–4.0"
        case .b40_45: "4.0–4.5"
        case .b45plus: "4.5+"
        case .unknown: "Don't care / unknown"
        }
    }

    public static func < (lhs: SkillBand, rhs: SkillBand) -> Bool {
        (lhs.ordinal ?? -1) < (rhs.ordinal ?? -1)
    }
}

public enum PlayCultureTag: String, ResilientEnum {
    case openPlay = "open_play"
    case organizedRotation = "organized_rotation"
    case challengeCourt = "challenge_court"
    case mostlyDoubles = "mostly_doubles"
    case singlesAvailable = "singles_available"
    case beginnerFriendly = "beginner_friendly"
    case casual, competitive, mixed, unknown
    public static let fallback = PlayCultureTag.unknown

    public var displayName: String {
        switch self {
        case .openPlay: "Open play"
        case .organizedRotation: "Organized rotation"
        case .challengeCourt: "Challenge court"
        case .mostlyDoubles: "Mostly doubles"
        case .singlesAvailable: "Singles available"
        case .beginnerFriendly: "Beginner friendly"
        case .casual: "Casual"
        case .competitive: "Competitive"
        case .mixed: "Mixed levels"
        case .unknown: "Unknown"
        }
    }
}

public enum SurfaceCondition: String, ResilientEnum {
    case dry
    case slightlyDamp = "slightly_damp"
    case wet
    case standingWater = "standing_water"
    case debris
    case iceSnow = "ice_snow"
    case construction
    case unsafe
    case unknown
    public static let fallback = SurfaceCondition.unknown

    /// Conditions that make play impossible or unsafe.
    public var isUnplayable: Bool { [.wet, .standingWater, .iceSnow, .construction, .unsafe].contains(self) }
    public var isDegraded: Bool { [.slightlyDamp, .debris].contains(self) }

    public var displayName: String {
        switch self {
        case .dry: "Dry"
        case .slightlyDamp: "Slightly damp"
        case .wet: "Wet"
        case .standingWater: "Standing water"
        case .debris: "Leaves / debris"
        case .iceSnow: "Ice / snow"
        case .construction: "Construction"
        case .unsafe: "Unsafe / damaged"
        case .unknown: "Unknown"
        }
    }
}

public enum OccupancyStatus: String, ResilientEnum {
    case courtsOpen = "courts_open"
    case mostlyFull = "mostly_full"
    case allFull = "all_full"
    case playersWaiting = "players_waiting"
    case unknown
    public static let fallback = OccupancyStatus.unknown

    /// Occupancy ratio and queued groups per court implied by a one-tap answer.
    public var implied: (occupancy: Double, queuePerCourt: Double)? {
        switch self {
        case .courtsOpen: (0.45, 0)
        case .mostlyFull: (0.85, 0)
        case .allFull: (1.0, 0.25)
        case .playersWaiting: (1.0, 1.0)
        case .unknown: nil
        }
    }

    public var displayName: String {
        switch self {
        case .courtsOpen: "Courts open"
        case .mostlyFull: "Mostly full"
        case .allFull: "All full"
        case .playersWaiting: "Players waiting"
        case .unknown: "Unknown"
        }
    }
}

/// One-tap paddle-stack answer. `representativePaddles` is the midpoint used by the wait model.
public enum PaddleStackLevel: String, ResilientEnum {
    case none, short, medium, long
    case unknown
    public static let fallback = PaddleStackLevel.unknown

    public var representativePaddles: Double? {
        switch self {
        case .none: 0
        case .short: 4
        case .medium: 9
        case .long: 16
        case .unknown: nil
        }
    }

    public static func from(paddles: Double) -> PaddleStackLevel {
        switch paddles {
        case ..<1: .none
        case ..<6: .short
        case ..<12: .medium
        default: .long
        }
    }

    public var displayName: String {
        switch self {
        case .none: "None"
        case .short: "Short"
        case .medium: "Medium"
        case .long: "Long"
        case .unknown: "Unknown"
        }
    }
}

/// Optional precise paddle count ranges ("How many paddles?").
public enum PaddleCountRange: String, ResilientEnum {
    case zero = "0"
    case r1_4 = "1-4"
    case r5_8 = "5-8"
    case r9_12 = "9-12"
    case r13_20 = "13-20"
    case r20plus = "20+"
    case unknown
    public static let fallback = PaddleCountRange.unknown

    public var midpoint: Double? {
        switch self {
        case .zero: 0
        case .r1_4: 2.5
        case .r5_8: 6.5
        case .r9_12: 10.5
        case .r13_20: 16.5
        case .r20plus: 24
        case .unknown: nil
        }
    }
}

public enum BlackoutReason: String, ResilientEnum {
    case tournament
    case leagueEvent = "league_event"
    case maintenance, construction
    case privateEvent = "private_event"
    case seasonalClosure = "seasonal_closure"
    case facilityClosure = "facility_closure"
    case other
    public static let fallback = BlackoutReason.other

    public var displayName: String {
        switch self {
        case .tournament: "Tournament"
        case .leagueEvent: "League event"
        case .maintenance: "Maintenance"
        case .construction: "Construction"
        case .privateEvent: "Private event"
        case .seasonalClosure: "Seasonal closure"
        case .facilityClosure: "Facility closure"
        case .other: "Unavailable"
        }
    }
}

/// Kinds of temporary operational override. Negative kinds propagate quickly (see docs §12).
public enum OverrideKind: String, ResilientEnum {
    case usableCourts = "usable_courts"
    case possibleClosure = "possible_closure"
    case temporarilyUnavailable = "temporarily_unavailable"
    case lockedGates = "locked_gates"
    case construction
    case netsRemoved = "nets_removed"
    case pickleballProhibited = "pickleball_prohibited"
    case unsafeSurface = "unsafe_surface"
    case tournament
    case unknown
    public static let fallback = OverrideKind.unknown

    public var isNegative: Bool { self != .usableCourts && self != .unknown }

    public var displayName: String {
        switch self {
        case .usableCourts: "Usable courts changed"
        case .possibleClosure: "Possible closure reported"
        case .temporarilyUnavailable: "Temporarily unavailable"
        case .lockedGates: "Gates reported locked"
        case .construction: "Construction reported"
        case .netsRemoved: "Nets reported removed"
        case .pickleballProhibited: "Pickleball reported prohibited"
        case .unsafeSurface: "Unsafe surface reported"
        case .tournament: "Tournament reported"
        case .unknown: "Issue reported"
        }
    }
}

public enum ConfidenceLevel: String, ResilientEnum, Comparable {
    case low, medium, high
    public static let fallback = ConfidenceLevel.low
    public var displayName: String { rawValue.capitalized + " confidence" }
    private var rank: Int { switch self { case .low: 0; case .medium: 1; case .high: 2 } }
    public static func < (l: ConfidenceLevel, r: ConfidenceLevel) -> Bool { l.rank < r.rank }
}
