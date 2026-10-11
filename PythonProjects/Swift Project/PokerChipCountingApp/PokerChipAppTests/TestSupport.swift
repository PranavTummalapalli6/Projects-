//
//  TestSupport.swift
//  PokerChipAppTests
//
//  Shared test doubles: a scripted network transport, and small builders.
//

import XCTest
@testable import PokerChipApp

// MARK: - A seeded random generator

/// A small deterministic generator, so a failing case can be reproduced from
/// the seed in the message.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - A scripted transport

/// Records what the client does and plays back canned responses in order.
final class Script {
    enum Step {
        case respond(status: Int, body: String)
        case fail(Error)
    }

    var steps: [Step]
    private(set) var requests: [URLRequest] = []
    private(set) var tokenRequests: [Bool] = []
    private(set) var sleeps: [Double] = []

    init(_ steps: [Step]) { self.steps = steps }

    func client(baseURL: String = "https://api.example.test", maxAttempts: Int = 3) -> ChipVisionAPIClient {
        ChipVisionAPIClient(
            transport: { [self] request in
                requests.append(request)
                guard !steps.isEmpty else { throw URLError(.badServerResponse) }
                switch steps.removeFirst() {
                case .respond(let status, let body):
                    let url = request.url ?? URL(fileURLWithPath: "/")
                    let response: URLResponse = HTTPURLResponse(
                        url: url, statusCode: status, httpVersion: nil, headerFields: nil
                    ) ?? URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
                    return (Data(body.utf8), response)
                case .fail(let error):
                    throw error
                }
            },
            baseURL: { URL(string: baseURL) ?? URL(fileURLWithPath: "/") },
            tokenProvider: { [self] forceRefresh in
                tokenRequests.append(forceRefresh)
                return forceRefresh ? "fresh-token" : "first-token"
            },
            sleep: { [self] seconds in sleeps.append(seconds) },
            maxAttempts: maxAttempts
        )
    }
}

/// A small night, for tests of how the client behaves in general.
let clientTestNight = GameNight.start(
    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
    now: Date(timeIntervalSince1970: 1_786_042_800),
    buyInMinor: 2_500,
    playerNames: ["Sam", "Alex"],
    colors: ["White"],
    denominationsMinor: ["White": 25]
)

/// The server's answer to a PUT: it holds the night as sent.
func putNightOK(_ night: GameNight = clientTestNight, applied: Bool = true) -> Script.Step {
    let object = (try? JSONSerialization.jsonObject(with: NightCoding.makeEncoder().encode(night))) ?? [String: Any]()
    let body = (try? JSONSerialization.data(withJSONObject: [
        "night": object, "applied": applied, "serverUpdatedAt": "2026-08-07T00:00:00.000001+00:00",
    ] as [String: Any])) ?? Data()
    return .respond(status: 200, body: String(decoding: body, as: UTF8.self))
}

func sendNight(_ client: ChipVisionAPIClient) async throws -> ChipVisionAPIClient.PutNightResult {
    try await client.putNight(clientTestNight)
}
