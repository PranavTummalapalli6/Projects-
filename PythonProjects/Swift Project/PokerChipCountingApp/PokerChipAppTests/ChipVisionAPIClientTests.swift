//
//  ChipVisionAPIClientTests.swift
//  PokerChipAppTests
//
//  The network client with the network replaced by a script: what it sends,
//  when it retries, when it gives up, and what it tells the person.
//

import XCTest
@testable import PokerChipApp

final class ChipVisionAPIClientTests: XCTestCase {

    // MARK: What it sends

    func testANightIsPutToItsOwnAddressAsJSON() async throws {
        let script = Script([putNightOK()])
        let result = try await sendNight(script.client())

        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.night, clientTestNight)
        let request = try XCTUnwrap(script.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/v1/nights/11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let sent = try NightCoding.makeDecoder().decode(GameNight.self, from: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(sent, clientTestNight)
    }

    func testRequestsGoToTheVersionedPathWithTheSignInToken() async throws {
        let script = Script([putNightOK()])
        _ = try await sendNight(script.client())

        let request = try XCTUnwrap(script.requests.first)
        XCTAssertTrue(request.url?.path.hasPrefix("/v1/") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer first-token")
    }

    func testTheServerKeepingItsOwnLaterVersionComesBackAsNotApplied() async throws {
        var theirs = clientTestNight
        theirs.notes = "edited elsewhere"
        let result = try await sendNight(Script([putNightOK(theirs, applied: false)]).client())
        XCTAssertFalse(result.applied)
        XCTAssertEqual(result.night.notes, "edited elsewhere")
    }

    func testFetchingNightsAsksFromTheCursorInPages() async throws {
        let body = #"{"nights": [], "cursor": "2026-08-07T00:00:05.000000+00:00", "hasMore": false}"#
        let script = Script([.respond(status: 200, body: body)])
        let page = try await script.client().fetchNights(since: "2026-08-07T00:00:00.000Z", limit: 50)

        XCTAssertEqual(page.cursor, "2026-08-07T00:00:05.000000+00:00")
        XCTAssertFalse(page.hasMore)
        let request = try XCTUnwrap(script.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first { $0.name == "since" }?.value, "2026-08-07T00:00:00.000Z")
        XCTAssertEqual(items?.first { $0.name == "limit" }?.value, "50")
    }

    func testTheFirstFetchSendsNoCursor() async throws {
        let script = Script([.respond(status: 200, body: #"{"nights": [], "cursor": null, "hasMore": false}"#)])
        let page = try await script.client().fetchNights(since: nil)
        XCTAssertNil(page.cursor)
        let items = URLComponents(url: try XCTUnwrap(script.requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertNil(items?.first { $0.name == "since" })
    }

    func testImportingEarlierSessionsReportsHowManyWereAdded() async throws {
        let script = Script([.respond(status: 200, body: #"{"imported": 3}"#)])
        let added = try await script.client().importLegacyNights()
        XCTAssertEqual(added, 3)
        XCTAssertEqual(script.requests.first?.httpMethod, "POST")
        XCTAssertEqual(script.requests.first?.url?.path, "/v1/nights/import-legacy")
    }

    func testAPhotoUploadIsMultipartWithTheChipValues() async throws {
        let script = Script([.respond(status: 200, body: #"{"counts": {"White": 3}, "confidence": "high", "photoUrl": ""}"#)])
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }

        let result = try await script.client().uploadPhoto(image: image, denominations: ["White": 0.25], sessionId: "s1")

        XCTAssertEqual(result.counts, ["White": 3])
        let request = try XCTUnwrap(script.requests.first)
        XCTAssertEqual(request.url?.path, "/v1/sessions/s1/photo")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains(#"name="denominations""#))
        XCTAssertTrue(body.contains(#"filename="chips.jpg""#))
        XCTAssertTrue(body.contains(#"{"White":0.25}"#))
    }

    func testDeletingAnAccountCallsTheAccountEndpoint() async throws {
        let script = Script([.respond(status: 204, body: "")])
        try await script.client().deleteAccount()

        XCTAssertEqual(script.requests.first?.httpMethod, "DELETE")
        XCTAssertEqual(script.requests.first?.url?.path, "/v1/account")
    }

    // MARK: Signing in again

    func testAnExpiredTokenIsRefreshedOnceAndTheRequestRepeated() async throws {
        let script = Script([.respond(status: 401, body: ""), putNightOK()])
        let result = try await sendNight(script.client())

        XCTAssertTrue(result.applied)
        XCTAssertEqual(script.tokenRequests, [false, true])
        XCTAssertEqual(script.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer first-token", "Bearer fresh-token"])
    }

    func testASecondRejectionMeansSignInAgain() async {
        let script = Script([.respond(status: 401, body: ""), .respond(status: 401, body: "")])
        do {
            _ = try await sendNight(script.client())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ChipVisionAPIError, .unauthorized)
        }
        XCTAssertEqual(script.requests.count, 2, "one refresh, not a loop")
    }

    func testNoSignedInUserMeansSignInAgain() async {
        let client = ChipVisionAPIClient(
            transport: { _ in throw URLError(.badServerResponse) },
            baseURL: { URL(string: "https://api.example.test") ?? URL(fileURLWithPath: "/") },
            tokenProvider: { _ in throw URLError(.userAuthenticationRequired) },
            sleep: { _ in }
        )
        do {
            _ = try await sendNight(client)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ChipVisionAPIError, .unauthorized)
        }
    }

    func testAFailedTokenRefreshBecauseOfNoSignalIsOfflineNotSignedOut() async {
        let client = ChipVisionAPIClient(
            transport: { _ in throw URLError(.badServerResponse) },
            baseURL: { URL(string: "https://api.example.test") ?? URL(fileURLWithPath: "/") },
            tokenProvider: { _ in throw NSError(domain: "FIRAuthErrorDomain", code: 17020) },
            sleep: { _ in }
        )
        do {
            _ = try await sendNight(client)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ChipVisionAPIError, .offline)
        }
    }

    // MARK: Retrying

    func testAServerHiccupIsRetriedWithBackoff() async throws {
        let script = Script([.respond(status: 503, body: ""), .respond(status: 502, body: ""), putNightOK()])
        let result = try await sendNight(script.client())

        XCTAssertTrue(result.applied)
        XCTAssertEqual(script.requests.count, 3)
        XCTAssertEqual(script.sleeps, [0.6, 1.5])
    }

    func testItStopsRetryingAfterTheLastAttempt() async {
        let script = Script([.respond(status: 503, body: ""), .respond(status: 503, body: ""), .respond(status: 503, body: "")])
        do {
            _ = try await sendNight(script.client())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ChipVisionAPIError, .server(status: 503, message: nil))
        }
        XCTAssertEqual(script.requests.count, 3)
    }

    func testATimeoutIsRetriedThenReportedAsATimeout() async {
        let script = Script([.fail(URLError(.timedOut)), .fail(URLError(.timedOut)), .fail(URLError(.timedOut))])
        do {
            _ = try await sendNight(script.client())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ChipVisionAPIError, .timedOut)
        }
        XCTAssertEqual(script.requests.count, 3)
        XCTAssertEqual(script.sleeps, [0.6, 1.5])
    }

    func testBeingOfflineIsReportedAtOnceWithoutRetrying() async {
        let script = Script([.fail(URLError(.notConnectedToInternet))])
        do {
            _ = try await sendNight(script.client())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ChipVisionAPIError, .offline)
        }
        XCTAssertEqual(script.requests.count, 1)
        XCTAssertTrue(script.sleeps.isEmpty)
    }

    func testACancelledRequestIsPassedThroughNotDressedUpAsAnError() async {
        let script = Script([.fail(URLError(.cancelled))])
        do {
            _ = try await sendNight(script.client())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
    }

    // MARK: Plain-language failures

    func testRateLimitingAndOversizedPhotosHaveTheirOwnMessages() async {
        for (status, expected) in [(429, ChipVisionAPIError.rateLimited), (413, .tooLarge)] {
            let script = Script([.respond(status: status, body: "")])
            do {
                _ = try await sendNight(script.client())
                XCTFail("expected an error for \(status)")
            } catch {
                XCTAssertEqual(error as? ChipVisionAPIError, expected)
            }
            XCTAssertEqual(script.requests.count, 1, "\(status) is not retried")
        }
    }

    func testTheServersOwnExplanationIsPassedAlong() async {
        let script = Script([.respond(status: 400, body: #"{"detail": "denominations must be valid JSON"}"#)])
        do {
            _ = try await sendNight(script.client())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ChipVisionAPIError, .server(status: 400, message: "denominations must be valid JSON"))
            XCTAssertEqual(error.localizedDescription, "denominations must be valid JSON")
        }
    }

    func testAGarbledSuccessResponseIsReportedAsUnexpected() async {
        let script = Script([.respond(status: 200, body: "<html>captive portal</html>")])
        do {
            _ = try await sendNight(script.client())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ChipVisionAPIError, .invalidResponse)
        }
    }

    func testAPlaceholderBackendAddressIsReportedBeforeAnythingIsSent() async {
        let script = Script([putNightOK()])
        do {
            _ = try await sendNight(script.client(baseURL: "https://REPLACE_WITH_CLOUD_RUN_URL"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ChipVisionAPIError, .notConfigured)
        }
        XCTAssertTrue(script.requests.isEmpty)
        XCTAssertTrue(script.tokenRequests.isEmpty)
    }

    func testEveryErrorExplainsItselfInWords() {
        let errors: [ChipVisionAPIError] = [
            .invalidImage, .invalidResponse, .notConfigured, .offline, .timedOut, .unreachable,
            .unauthorized, .rateLimited, .tooLarge, .server(status: 500, message: nil),
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty, "\(error)")
            XCTAssertFalse(error.localizedDescription.contains("ChipVisionAPIError"), "\(error)")
        }
    }
}
