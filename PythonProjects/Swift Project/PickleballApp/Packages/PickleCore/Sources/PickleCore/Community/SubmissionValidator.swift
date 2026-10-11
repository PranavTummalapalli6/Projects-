import Foundation

/// Minimal "Add a court" submission. Only `location` is required.
public struct FacilitySubmissionDraft: Codable, Hashable, Sendable {
    public var location: GeoPoint?
    public var name: String = ""
    public var courtCount: Int?
    public var courtType: CourtType = .unknown
    public var indoorOutdoor: IndoorOutdoor = .outdoor
    public var hasLights: Bool?
    public var accessType: AccessType = .unknown
    public var costType: AccessCostType = .unknown
    public var playSystem: PlaySystem = .unknown
    public var notes: String = ""
    public var hoursNote: String = ""

    public init(location: GeoPoint? = nil) { self.location = location }
}

public enum SubmissionIssue: Hashable, Sendable {
    case missingLocation, invalidLocation, courtCountOutOfRange, nameTooLong, notesTooLong, nameLooksLikeSpam

    public var message: String {
        switch self {
        case .missingLocation: "Choose where the courts are"
        case .invalidLocation: "That location doesn't look right"
        case .courtCountOutOfRange: "Court count should be between 1 and 60"
        case .nameTooLong: "Name is too long (120 characters max)"
        case .notesTooLong: "Notes are too long (500 characters max)"
        case .nameLooksLikeSpam: "Please enter the facility's real name"
        }
    }
}

public enum SubmissionValidator {
    public static func validate(_ d: FacilitySubmissionDraft) -> [SubmissionIssue] {
        var issues: [SubmissionIssue] = []
        if let loc = d.location { if !loc.isValid { issues.append(.invalidLocation) } } else { issues.append(.missingLocation) }
        if let c = d.courtCount, !(1...60).contains(c) { issues.append(.courtCountOutOfRange) }
        let name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.count > 120 { issues.append(.nameTooLong) }
        if name.contains("http") || name.contains("www.") || name.contains("@") { issues.append(.nameLooksLikeSpam) }
        if d.notes.count > 500 || d.hoursNote.count > 500 { issues.append(.notesTooLong) }
        return issues
    }
}
