import Foundation

/// Typed errors surfaced by repositories. Views map these to friendly empty/error states.
enum APIError: Error, Equatable, LocalizedError {
    case offline
    case timeout
    case unauthorized
    case rateLimited
    case invalidInput(String)
    case server(status: Int, message: String)
    case network(String)
    case decoding(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .offline: "You're offline. Showing what we last loaded."
        case .timeout: "The connection timed out. Try again."
        case .unauthorized: "Your session expired. Please try again."
        case .rateLimited: "You've shared a lot recently — thanks! Try again a bit later."
        case .invalidInput(let m): m
        case .server: "Something went wrong on our side. Try again shortly."
        case .network: "Couldn't reach the server. Check your connection."
        case .decoding: "We received data we couldn't read. Please update the app."
        case .notConfigured: "Backend not configured."
        }
    }

    var isConnectivity: Bool { self == .offline || self == .timeout || { if case .network = self { true } else { false } }() }
}
