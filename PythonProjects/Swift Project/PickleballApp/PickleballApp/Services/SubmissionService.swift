import Foundation
import PickleCore
import UIKit

/// Add-a-court and suggest-an-edit flows, plus privacy-preserving photo preparation.
struct SubmissionService: Sendable {
    let repository: SubmissionRepository
    let analytics: ProfileRepository

    func duplicates(at point: GeoPoint, name: String?) async throws -> [DuplicateCandidateDTO] {
        try await repository.findDuplicates(at: point, name: name)
    }

    func submit(_ draft: FacilitySubmissionDraft, forceNew: Bool, userFix: LocationFix?) async throws -> SubmissionResult {
        let issues = SubmissionValidator.validate(draft)
        if let first = issues.first { return SubmissionResult(status: "invalid", reason: first.message) }
        let result = try await repository.submitFacility(draft, forceNew: forceNew, userFix: userFix)
        if result.status == "created" { await analytics.logEvent("court_added", facilityID: result.facilityId, props: [:]) }
        return result
    }

    func suggestEdit(_ f: Facility, type: EditType, proposed: [String: JSONValue], note: String?, fix: LocationFix?) async throws -> EditResult {
        let result = try await repository.suggestEdit(facilityID: f.id, type: type, proposed: proposed, note: note, fix: fix)
        await analytics.logEvent("edit_suggested", facilityID: f.id, props: ["type": .string(type.rawValue)])
        return result
    }

    /// Re-encodes to JPEG ≤ 1600 px. Drawing into a fresh context drops EXIF/GPS metadata entirely.
    static func preparePhoto(_ data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> (jpeg: Data, width: Int, height: Int)? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = rendered.jpegData(compressionQuality: quality) else { return nil }
        return (jpeg, Int(size.width), Int(size.height))
    }

    func uploadPhoto(_ data: Data, facilityID: UUID?, submissionID: UUID?) async throws {
        guard let prepared = Self.preparePhoto(data) else { throw APIError.invalidInput("That photo couldn't be read") }
        try await repository.uploadPhoto(jpeg: prepared.jpeg, facilityID: facilityID, submissionID: submissionID,
                                         width: prepared.width, height: prepared.height)
    }
}
