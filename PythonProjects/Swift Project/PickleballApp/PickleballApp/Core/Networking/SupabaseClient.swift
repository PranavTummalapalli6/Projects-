import Foundation
import PickleCore

/// JSON value used to build RPC parameter objects without losing `null`s.
enum JSONValue: Encodable, Hashable, Sendable {
    case string(String), number(Double), int(Int), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    static func of(_ v: String?) -> JSONValue { v.map(JSONValue.string) ?? .null }
    static func of(_ v: Double?) -> JSONValue { v.flatMap { $0.isFinite ? JSONValue.number($0) : nil } ?? .null }
    static func of(_ v: Int?) -> JSONValue { v.map(JSONValue.int) ?? .null }
    static func of(_ v: Bool?) -> JSONValue { v.map(JSONValue.bool) ?? .null }
    static func of(_ v: UUID?) -> JSONValue { v.map { .string($0.uuidString.lowercased()) } ?? .null }
    static func of(_ v: Date?) -> JSONValue { v.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null }
}

typealias RPCParams = [String: JSONValue]

struct AuthSession: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: UUID
}

/// Minimal Supabase client: PostgREST RPC, anonymous auth with refresh, Storage upload, Edge Functions.
/// Only the public anon key ships in the app; the service-role key never does.
actor SupabaseClient {
    let baseURL: URL
    private let anonKey: String
    private let session: URLSession
    private let keychain: KeychainStore
    private var auth: AuthSession?
    private var signInTask: Task<AuthSession, Error>?
    private static let keychainKey = "supabase.session"

    init(baseURL: URL, anonKey: String, keychain: KeychainStore = KeychainStore(service: "PickleballNow")) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.keychain = keychain
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
        if let data = keychain.read(Self.keychainKey) {
            self.auth = try? JSONDecoder().decode(AuthSession.self, from: data)
        }
    }

    var currentUserID: UUID? { auth?.userID }

    // MARK: Auth

    /// Returns a valid session, creating an anonymous one only when needed (first contribution).
    func ensureSession() async throws -> AuthSession {
        if let auth, auth.expiresAt.timeIntervalSinceNow > 60 { return auth }
        if let task = signInTask { return try await task.value }
        let existing = auth
        let task = Task { () throws -> AuthSession in
            if let existing, let refreshed = try? await refresh(existing) { return refreshed }
            return try await signInAnonymously()
        }
        signInTask = task
        defer { signInTask = nil }
        let s = try await task.value
        store(s)
        return s
    }

    private func store(_ s: AuthSession) {
        auth = s
        if let data = try? JSONEncoder().encode(s) { keychain.write(Self.keychainKey, data: data) }
    }

    private struct TokenResponse: Decodable {
        struct User: Decodable { let id: UUID }
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
        let user: User
    }

    private func signInAnonymously() async throws -> AuthSession {
        var req = URLRequest(url: baseURL.appending(path: "auth/v1/signup"))
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let token: TokenResponse = try await send(req)
        return AuthSession(accessToken: token.accessToken, refreshToken: token.refreshToken,
                           expiresAt: Date().addingTimeInterval(token.expiresIn), userID: token.user.id)
    }

    private func refresh(_ s: AuthSession) async throws -> AuthSession {
        var comps = URLComponents(url: baseURL.appending(path: "auth/v1/token"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["refresh_token": s.refreshToken])
        let token: TokenResponse = try await send(req)
        return AuthSession(accessToken: token.accessToken, refreshToken: token.refreshToken,
                           expiresAt: Date().addingTimeInterval(token.expiresIn), userID: token.user.id)
    }

    // MARK: RPC

    /// - Parameter requiresUser: create/refresh an anonymous session first. Reads pass the user token
    ///   only if one already exists, so browsing never forces account creation.
    func rpc<T: Decodable>(_ name: String, _ params: RPCParams = [:], requiresUser: Bool = false,
                           as type: T.Type = T.self) async throws -> T {
        var req = URLRequest(url: baseURL.appending(path: "rest/v1/rpc/\(name)"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(params)
        try await authorize(&req, requiresUser: requiresUser)
        do {
            return try await send(req)
        } catch APIError.unauthorized where !requiresUser && auth != nil {
            // Stale token on a read: retry as signed-out.
            auth = nil
            keychain.delete(Self.keychainKey)
            try await authorize(&req, requiresUser: false)
            return try await send(req)
        }
    }

    func uploadObject(bucket: String, path: String, data: Data, contentType: String) async throws {
        var req = URLRequest(url: baseURL.appending(path: "storage/v1/object/\(bucket)/\(path)"))
        req.httpMethod = "POST"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("false", forHTTPHeaderField: "x-upsert")
        req.httpBody = data
        try await authorize(&req, requiresUser: true)
        let _: IgnoredResponse = try await send(req)
    }

    func invokeFunction<T: Decodable>(_ name: String, body: RPCParams) async throws -> T {
        var req = URLRequest(url: baseURL.appending(path: "functions/v1/\(name)"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 45
        try await authorize(&req, requiresUser: false)
        return try await send(req)
    }

    private func authorize(_ req: inout URLRequest, requiresUser: Bool) async throws {
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        if requiresUser {
            let s = try await ensureSession()
            req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        } else if let s = auth, s.expiresAt.timeIntervalSinceNow > 60 {
            req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }
    }

    private struct IgnoredResponse: Decodable {
        init(from decoder: Decoder) throws {}
    }

    private struct PostgrestError: Decodable {
        let code: String?
        let message: String?
        let msg: String?
        let error: String?
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                throw APIError.offline
            case .timedOut: throw APIError.timeout
            case .cancelled: throw CancellationError()
            default: throw APIError.network(error.localizedDescription)
            }
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.network("No response") }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONDecoder().decode(PostgrestError.self, from: data)
            let message = body?.message ?? body?.msg ?? body?.error ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            switch (http.statusCode, body?.code) {
            case (401, _), (_, "28000"), (_, "PGRST301"): throw APIError.unauthorized
            case (_, "22023"), (400, _): throw APIError.invalidInput(message)
            case (429, _): throw APIError.rateLimited
            default: throw APIError.server(status: http.statusCode, message: message)
            }
        }
        if T.self == IgnoredResponse.self { return try IgnoredResponse(from: EmptyDecoder()) as! T }
        do {
            return try JSONCoding.decoder.decode(T.self, from: data.isEmpty ? Data("null".utf8) : data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

private struct EmptyDecoder: Decoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "empty"))
    }
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "empty"))
    }
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "empty"))
    }
}
