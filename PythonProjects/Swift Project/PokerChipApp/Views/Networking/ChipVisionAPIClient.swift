//
//  ChipVisionAPIClient.swift
//  PokerChipApp
//
//  Talks to the ChipVisionService backend: uploads the end-of-game photo for
//  best-effort chip detection, then submits the user-confirmed final counts.
//

import UIKit
import Foundation

enum ChipVisionAPIError: LocalizedError {
    case invalidImage
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Couldn't process that photo."
        case .invalidResponse: return "The server sent back something unexpected."
        case .server(let message): return message
        }
    }
}

struct ChipVisionAPIClient {
    static let shared = ChipVisionAPIClient()

    /// Uploads the captured photo for automatic detection. The photo lives only in
    /// memory on the client — it's converted to JPEG data here and never written to
    /// disk or the Photos library; ChipVisionService is the system of record for it.
    func uploadPhoto(
        image: UIImage,
        denominations: [String: Double],
        sessionId: String
    ) async throws -> ChipDetectionResult {
        guard let jpegData = image.jpegData(compressionQuality: 0.7) else {
            throw ChipVisionAPIError.invalidImage
        }

        let idToken = try await AuthenticationManager.shared.currentIdToken()
        var request = URLRequest(url: APIConfig.baseURL.appendingPathComponent("v1/sessions/\(sessionId)/photo"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let denominationsJSON = try JSONSerialization.data(withJSONObject: denominations)
        body.appendFormField(name: "denominations", value: String(data: denominationsJSON, encoding: .utf8) ?? "{}", boundary: boundary)
        body.appendFormFile(name: "image", filename: "chips.jpg", mimeType: "image/jpeg", fileData: jpegData, boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)
        return try JSONDecoder().decode(ChipDetectionResult.self, from: data)
    }

    /// Submits the user's confirmed final counts. The backend recomputes profit/loss
    /// itself rather than trusting client arithmetic for the stored record.
    func completeSession(
        sessionId: String,
        buyIn: Double,
        denominations: [String: Double],
        finalCounts: [String: Int],
        elapsedSeconds: Int
    ) async throws -> SessionResult {
        let idToken = try await AuthenticationManager.shared.currentIdToken()
        var request = URLRequest(url: APIConfig.baseURL.appendingPathComponent("v1/sessions/\(sessionId)/complete"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "buyIn": buyIn,
            "denominations": denominations,
            "finalCounts": finalCounts,
            "elapsedSeconds": elapsedSeconds,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)
        return try JSONDecoder().decode(SessionResult.self, from: data)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChipVisionAPIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ChipVisionAPIError.server("Server returned status \(httpResponse.statusCode).")
        }
    }
}

private extension Data {
    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendFormFile(name: String, filename: String, mimeType: String, fileData: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(fileData)
        append("\r\n".data(using: .utf8)!)
    }
}
