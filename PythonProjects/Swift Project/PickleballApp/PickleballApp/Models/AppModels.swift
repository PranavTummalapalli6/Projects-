import Foundation
import PickleCore

struct FacilityRule: Decodable, Hashable, Sendable {
    var kind: String
    var text: String
}

/// `facility_detail` payload: the facility plus progressive-disclosure extras.
struct FacilityDetail: Decodable, Sendable {
    var facility: Facility
    var weekBuckets: [HistoricalBucket]
    var rules: [FacilityRule]
    var photos: [String]
    var sources: [String]
    var myConfirmation: String?
    var confirmationCount: Int?
}

struct ContributorStatus: Decodable, Equatable, Sendable {
    var insightsUntil: Date?
    var qualifyingContributions: Int
    var hasLiveInsights: Bool
    var liveGatingEnabled: Bool

    static let unknown = ContributorStatus(insightsUntil: nil, qualifyingContributions: 0, hasLiveInsights: false, liveGatingEnabled: false)
}

/// What the user is reporting with one tap. Raw values match `submit_live_report.p_kind`.
enum LiveReportKind: String, Sendable {
    case occupancy, paddleStack = "paddle_stack", surface, usableCourts = "usable_courts", skill, culture
}

struct LiveReportRequest: Sendable {
    var facilityID: UUID
    var kind: LiveReportKind
    var value: String?
    var count: Int?
    var groupsWaiting: Int?
    var fix: LocationFix?
    var clientReportID = UUID()
}

struct LiveReportResult: Decodable, Sendable {
    var accepted: Bool
    var reason: String?
    var locationVerified: Bool?
    var insightsUntil: Date?
    var state: String?

    var userMessage: String {
        if accepted { return "Thanks for helping nearby players." }
        switch reason {
        case "too_soon": return "You just reported this — thanks! You can update it again in a few minutes."
        case "not_nearby": return "Live reports open when you're at the courts."
        case "rate_limited": return "You've shared a lot recently — thanks! Try again a bit later."
        case "facility_not_found": return "This facility is no longer listed."
        default: return "We couldn't save that report."
        }
    }
}

enum IssueKind: String, CaseIterable, Identifiable, Sendable {
    case lockedGates = "locked_gates"
    case tournament
    case construction
    case netsRemoved = "nets_removed"
    case unsafeSurface = "unsafe_surface"
    case temporarilyUnavailable = "temporarily_unavailable"
    case pickleballProhibited = "pickleball_prohibited"
    case possibleClosure = "possible_closure"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .lockedGates: "Gates locked"
        case .tournament: "Tournament / event"
        case .construction: "Construction"
        case .netsRemoved: "Nets removed"
        case .unsafeSurface: "Unsafe surface"
        case .temporarilyUnavailable: "Closed today"
        case .pickleballProhibited: "No pickleball allowed"
        case .possibleClosure: "Permanently closed"
        }
    }
    var symbol: String {
        switch self {
        case .lockedGates: "lock.fill"
        case .tournament: "trophy.fill"
        case .construction: "hammer.fill"
        case .netsRemoved: "minus.rectangle"
        case .unsafeSurface: "exclamationmark.triangle.fill"
        case .temporarilyUnavailable: "clock.badge.xmark"
        case .pickleballProhibited: "nosign"
        case .possibleClosure: "xmark.octagon.fill"
        }
    }
}

struct DuplicateCandidateDTO: Decodable, Hashable, Identifiable, Sendable {
    var facilityId: UUID
    var name: String
    var distanceMeters: Double
    var nameSimilarity: Double?
    var existenceStatus: VerificationStatus?
    var latitude: Double?
    var longitude: Double?
    var id: UUID { facilityId }
}

struct SubmissionResult: Decodable, Sendable {
    var status: String           // created | duplicate_candidates | invalid | rate_limited
    var reason: String?
    var facilityId: UUID?
    var submissionId: UUID?
    var existenceStatus: VerificationStatus?
    var candidates: [DuplicateCandidateDTO]?
    var insightsUntil: Date?
}

struct ConfirmationResult: Decodable, Sendable {
    var accepted: Bool
    var reason: String?
    var existenceStatus: VerificationStatus?
}

enum EditType: String, CaseIterable, Identifiable, Sendable {
    case courtCountChanged = "court_count_changed"
    case pickleballCourtsAdded = "pickleball_courts_added"
    case stripedForPickleball = "striped_for_pickleball"
    case convertedToDedicated = "converted_to_dedicated"
    case indoorOutdoorChanged = "indoor_outdoor_changed"
    case accessChanged = "access_changed"
    case costChanged = "cost_changed"
    case reservationPolicyChanged = "reservation_policy_changed"
    case playSystemChanged = "play_system_changed"
    case hoursChanged = "hours_changed"
    case amenitiesChanged = "amenities_changed"
    case noLongerPickleball = "no_longer_pickleball"
    case permanentlyClosed = "permanently_closed"
    case other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .courtCountChanged: "Court count changed"
        case .pickleballCourtsAdded: "Pickleball courts added"
        case .stripedForPickleball: "Tennis courts now have pickleball lines"
        case .convertedToDedicated: "Converted to dedicated pickleball"
        case .indoorOutdoorChanged: "Indoor / outdoor is wrong"
        case .accessChanged: "Access rules changed"
        case .costChanged: "Price changed"
        case .reservationPolicyChanged: "Reservation policy changed"
        case .playSystemChanged: "How people rotate changed"
        case .hoursChanged: "Hours changed"
        case .amenitiesChanged: "Lights / amenities changed"
        case .noLongerPickleball: "No longer supports pickleball"
        case .permanentlyClosed: "Permanently closed"
        case .other: "Something else"
        }
    }
    var symbol: String {
        switch self {
        case .courtCountChanged, .pickleballCourtsAdded: "number.square"
        case .stripedForPickleball: "rectangle.split.2x1"
        case .convertedToDedicated: "figure.pickleball"
        case .indoorOutdoorChanged: "house.and.flag"
        case .accessChanged: "person.badge.key"
        case .costChanged: "dollarsign.circle"
        case .reservationPolicyChanged: "calendar.badge.clock"
        case .playSystemChanged: "arrow.triangle.2.circlepath"
        case .hoursChanged: "clock"
        case .amenitiesChanged: "lightbulb"
        case .noLongerPickleball: "nosign"
        case .permanentlyClosed: "xmark.octagon"
        case .other: "ellipsis.bubble"
        }
    }
}

struct EditResult: Decodable, Sendable {
    var status: String
    var suggestionId: UUID?
}

struct RegionDiscoveryResult: Decodable, Sendable {
    var geohash: String?
    var action: String          // fresh | imported | busy | deferred | failed
    var facilityCount: Int?
    var inserted: Int?
}

struct VisitRecord: Sendable {
    var facilityID: UUID
    var arrival: Date
    var departure: Date?
    var method: String = "foreground"
    var confidence: Double = 0.6
}
