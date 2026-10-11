//
//  ChipVisionAPIClient.swift
//  PokerChipApp
//
//  Talks to the ChipVisionService backend: uploads a chip photo for
//  best-effort counting, keeps game nights in step between devices, and
//  deletes an account.
//
//  Every call has a bounded timeout, retries transient failures with backoff,
//  refreshes an expired sign-in token once, and fails with an error that says
//  what to do next — nothing here should leave a person staring at a spinner.
//

import Foundation
import UIKit

enum ChipVisionAPIError: LocalizedError, Equatable {
    case invalidImage
    case invalidResponse
    case notConfigured
    case offline
    case timedOut
    case unreachable
    case unauthorized
    case rateLimited
    case tooLarge
    case server(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "That photo couldn't be read. Try taking it again."
        case .invalidResponse: return "The counting service sent back something unexpected."
        case .notConfigured: return "The counting service isn't set up in this build."
        case .offline: return "You're offline."
        case .timedOut: return "The counting service took too long to respond."
        case .unreachable: return "Couldn't reach the counting service."
        case .unauthorized: return "Your sign-in has expired. Sign in again to continue."
        case .rateLimited: return "You've sent a lot of photos. Wait a few minutes and try again."
        case .tooLarge: return "That photo is too large. Try a smaller one."
        case .server(let status, let message): return message ?? "The service had a problem (code \(status))."
        }
    }
}

struct ChipVisionAPIClient {
    /// Sends one request and returns the raw response. Replaceable so tests
    /// and UI-test mode can answer without a network.
    var transport: (URLRequest) async throws -> (Data, URLResponse)
    var baseURL: () -> URL
    /// The Firebase ID token; `forceRefresh` is set after a 401.
    var tokenProvider: (_ forceRefresh: Bool) async throws -> String
    var sleep: (_ seconds: Double) async -> Void
    var maxAttempts = 3

    static let shared: ChipVisionAPIClient = {
        #if DEBUG
        if AppEnvironment.isUITest { return .uiTestStub }
        #endif
        return .live
    }()

    static var live: ChipVisionAPIClient {
        let configuration = URLSessionConfiguration.default
        // Idle timeout, not total: a photo upload on a slow connection can run
        // long as long as it keeps moving. The resource timeout is the ceiling.
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)

        return ChipVisionAPIClient(
            transport: { try await session.data(for: $0) },
            baseURL: { APIConfig.baseURL },
            tokenProvider: { try await AuthenticationManager.shared.currentIdToken(forceRefresh: $0) },
            sleep: { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
        )
    }

    // MARK: Endpoints

    /// Uploads the captured photo for automatic detection. The photo lives
    /// only in memory on the client — it's converted to JPEG data here and
    /// never written to disk or the Photos library; ChipVisionService is the
    /// system of record for it.
    ///
    /// A photo taken from the side is read as piles, and sends the camera's pose so
    /// the service knows how the chips are foreshortened; nothing else about how the
    /// photo was taken leaves the phone.
    func uploadPhoto(
        image: UIImage,
        denominations: [String: Double],
        sessionId: String,
        angle: PhotoAngle = .above,
        pose: CameraPose? = nil,
        colors: [String] = []
    ) async throws -> ChipDetectionResult {
        // Resizing and JPEG-encoding a full-resolution photo is real work: keep
        // it off the main thread so the screen doesn't stutter as the upload starts.
        let jpegData = await Task.detached(priority: .userInitiated) {
            image.preparedForUpload().jpegData(compressionQuality: 0.7)
        }.value
        guard let jpegData else { throw ChipVisionAPIError.invalidImage }

        let denominationsJSON = try JSONSerialization.data(withJSONObject: denominations)
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendFormField(
            name: "denominations",
            value: String(data: denominationsJSON, encoding: .utf8) ?? "{}",
            boundary: boundary
        )
        if angle == .side {
            body.appendFormField(name: "view", value: angle.serviceName, boundary: boundary)
            if let pose {
                body.appendFormField(name: "pitch", value: String(format: "%.1f", pose.pitchDegrees), boundary: boundary)
                if let roll = pose.rollDegrees {
                    body.appendFormField(name: "roll", value: String(format: "%.1f", roll), boundary: boundary)
                }
                if let focal = pose.focal35mm {
                    body.appendFormField(name: "focal35", value: String(format: "%.0f", focal), boundary: boundary)
                }
            }
            if !colors.isEmpty {
                body.appendFormField(name: "colors", value: colors.joined(separator: ","), boundary: boundary)
            }
        }
        body.appendFormFile(name: "image", filename: "chips.jpg", mimeType: "image/jpeg", fileData: jpegData, boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let url = baseURL().appendingPathComponent("v1/sessions/\(sessionId)/photo")
        let data = try await perform {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            return request
        }
        return try Self.decode(ChipDetectionResult.self, from: data)
    }

    // MARK: Nights

    struct PutNightResult {
        /// The version the server now holds. When `applied` is false that is the
        /// server's own, later version, which the app adopts.
        var night: GameNight
        var applied: Bool
        var serverUpdatedAt: String
    }

    struct NightPage {
        var nights: [GameNight]
        /// Pass back as `since` to continue.
        var cursor: String?
        var hasMore: Bool
    }

    /// Saves one night. Safe to repeat: the server keeps the later edit and
    /// answers `applied: false` with its own version if it already has one.
    func putNight(_ night: GameNight) async throws -> PutNightResult {
        let body = try NightCoding.makeEncoder().encode(night)
        let url = baseURL().appendingPathComponent("v1/nights/\(night.id.uuidString)")
        let data = try await perform {
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            return request
        }
        struct Envelope: Decodable {
            var night: GameNight
            var applied: Bool
            var serverUpdatedAt: String
        }
        let envelope = try Self.decodeNights(Envelope.self, from: data)
        return PutNightResult(night: envelope.night, applied: envelope.applied, serverUpdatedAt: envelope.serverUpdatedAt)
    }

    /// Nights (and deletions) changed since a cursor from an earlier call.
    func fetchNights(since: String?, limit: Int = 100) async throws -> NightPage {
        var components = URLComponents(url: baseURL().appendingPathComponent("v1/nights"), resolvingAgainstBaseURL: false)
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let since { items.append(URLQueryItem(name: "since", value: since)) }
        components?.queryItems = items
        guard let url = components?.url else { throw ChipVisionAPIError.invalidResponse }

        let data = try await perform {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            return request
        }
        struct Envelope: Decodable {
            var nights: [GameNight]
            var cursor: String?
            var hasMore: Bool
        }
        let envelope = try Self.decodeNights(Envelope.self, from: data)
        return NightPage(nights: envelope.nights, cursor: envelope.cursor, hasMore: envelope.hasMore)
    }

    /// Asks the server to turn this account's old single-player sessions into
    /// nights. Returns how many were added; repeating is harmless.
    func importLegacyNights() async throws -> Int {
        let url = baseURL().appendingPathComponent("v1/nights/import-legacy")
        let data = try await perform {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            return request
        }
        struct Envelope: Decodable { var imported: Int }
        return try Self.decode(Envelope.self, from: data).imported
    }

    /// A short-lived link to the photo stored for one cash-out, or nil if none is.
    func fetchPhotoURL(sessionId: String) async throws -> URL? {
        let url = baseURL().appendingPathComponent("v1/sessions/\(sessionId)/photo-url")
        do {
            let data = try await perform {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                return request
            }
            struct Envelope: Decodable { var photoUrl: String }
            return URL(string: try Self.decode(Envelope.self, from: data).photoUrl)
        } catch ChipVisionAPIError.server(let status, _) where status == 404 {
            return nil
        }
    }

    /// Wakes the counting service ahead of a photo. It scales to zero when idle
    /// and its first answer can take several seconds; asking early means the
    /// person isn't the one waiting. Best effort: it never throws, and it needs
    /// no sign-in.
    func prewarm() async {
        guard !baseURL().absoluteString.contains("REPLACE_WITH") else { return }
        var request = URLRequest(url: baseURL().appendingPathComponent("healthz"))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        _ = try? await transport(request)
    }

    /// Deletes the account and everything stored for it (records, photos,
    /// and the sign-in itself).
    func deleteAccount() async throws {
        let url = baseURL().appendingPathComponent("v1/account")
        _ = try await perform {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            return request
        }
    }

    // MARK: Plumbing

    private func perform(_ makeRequest: () -> URLRequest) async throws -> Data {
        if baseURL().absoluteString.contains("REPLACE_WITH") {
            throw ChipVisionAPIError.notConfigured
        }

        var token = try await fetchToken(forceRefresh: false)
        var refreshedToken = false
        var attempt = 0

        while true {
            attempt += 1
            var request = makeRequest()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await transport(request)
                guard let http = response as? HTTPURLResponse else {
                    throw ChipVisionAPIError.invalidResponse
                }
                switch http.statusCode {
                case 200...299:
                    return data
                case 401 where !refreshedToken:
                    // The ID token expires hourly; ask for a fresh one once.
                    refreshedToken = true
                    token = try await fetchToken(forceRefresh: true)
                    continue
                case 401:
                    throw ChipVisionAPIError.unauthorized
                case 413:
                    throw ChipVisionAPIError.tooLarge
                case 429:
                    throw ChipVisionAPIError.rateLimited
                case 502...504 where attempt < maxAttempts:
                    await sleep(Self.backoff(afterAttempt: attempt))
                    continue
                default:
                    throw ChipVisionAPIError.server(status: http.statusCode, message: Self.detail(in: data))
                }
            } catch let error as URLError {
                if error.code == .cancelled { throw error }
                let (mapped, isTransient) = Self.classify(error)
                if isTransient && attempt < maxAttempts {
                    await sleep(Self.backoff(afterAttempt: attempt))
                    continue
                }
                throw mapped
            }
        }
    }

    private func fetchToken(forceRefresh: Bool) async throws -> String {
        do {
            return try await tokenProvider(forceRefresh)
        } catch {
            // No signed-in user, or Firebase couldn't refresh the token. A
            // network failure while refreshing is "offline", not "signed out".
            let nsError = error as NSError
            if nsError.domain == "FIRAuthErrorDomain" && nsError.code == 17020 {
                throw ChipVisionAPIError.offline
            }
            throw ChipVisionAPIError.unauthorized
        }
    }

    private static func classify(_ error: URLError) -> (error: ChipVisionAPIError, isTransient: Bool) {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return (.offline, false)
        case .timedOut:
            return (.timedOut, true)
        case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return (.unreachable, true)
        default:
            return (.unreachable, false)
        }
    }

    /// 0.6 s, then 1.5 s — long enough for a cold-starting service, short
    /// enough that three attempts still finish well inside a minute.
    static func backoff(afterAttempt attempt: Int) -> Double {
        attempt <= 1 ? 0.6 : 1.5
    }

    /// FastAPI error bodies look like {"detail": "..."}.
    private static func detail(in data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let detail = object["detail"] as? String
        else { return nil }
        return detail
    }

    private static func decodeNights<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try NightCoding.makeDecoder().decode(type, from: data)
        } catch {
            throw ChipVisionAPIError.invalidResponse
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ChipVisionAPIError.invalidResponse
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
