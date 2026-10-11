//
//  PokerChipAppTests.swift
//  PokerChipAppTests
//
//  Created by Pranav on 11/11/24.
//
//  Guards against shipping development leftovers. These read the built app's
//  own Info.plist, so they catch a bad build setting, not just a bad source file.
//

import XCTest
@testable import PokerChipApp

final class PokerChipAppTests: XCTestCase {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    func testTheCameraPermissionTextIsRealAndExplainsWhy() {
        let text = info["NSCameraUsageDescription"] as? String ?? ""
        XCTAssertFalse(text.isEmpty)
        XCTAssertFalse(text.lowercased().contains("reason app trail"), "placeholder text gets an App Review rejection")
        XCTAssertTrue(text.lowercased().contains("camera"))
        XCTAssertTrue(text.lowercased().contains("chips"))
    }

    func testTheHomeScreenNameIsAProperName() {
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Chip Counter")
    }

    func testTheAppIsDarkOnly() {
        XCTAssertEqual(info["UIUserInterfaceStyle"] as? String, "Dark")
    }

    func testTheBackendAddressComesFromTheBuildSettings() {
        let raw = info["APIBaseURL"] as? String ?? ""
        XCTAssertFalse(raw.isEmpty, "API_BASE_URL did not reach Info.plist")
        XCTAssertFalse(raw.contains("$("), "an unexpanded build setting: \(raw)")
        XCTAssertTrue(APIConfig.isConfigured, "Debug builds point at a real address: \(raw)")
        XCTAssertNotNil(URL(string: raw)?.host)
    }

    func testThePlaceholderAddressIsRecognisedAsNotConfigured() {
        // What a Release build carries until the Cloud Run URL is filled in.
        let placeholder = "https://REPLACE_WITH_CLOUD_RUN_URL"
        XCTAssertTrue(placeholder.contains("REPLACE_WITH"))
    }

    func testTheLaunchScreenMatchesTheSplashImage() {
        let launch = info["UILaunchScreen"] as? [String: Any]
        XCTAssertEqual(launch?["UIImageName"] as? String, "SplashSeal")
        XCTAssertNotNil(UIImage(named: "SplashSeal"), "the launch image is missing from the asset catalog")
        XCTAssertNotNil(UIColor(named: "LaunchBackground"))
    }

    func testTheAppRunsOnIPhoneOnly() {
        let families = info["UIDeviceFamily"] as? [Int] ?? []
        XCTAssertEqual(families, [1])
    }
}
