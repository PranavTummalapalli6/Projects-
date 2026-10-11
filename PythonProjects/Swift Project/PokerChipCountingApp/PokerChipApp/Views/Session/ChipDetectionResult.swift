//
//  ChipDetectionResult.swift
//  PokerChipApp
//

import Foundation

/// One chip the counting service found: its centre and radius, each as a fraction
/// of the photo's width.
struct ChipDetection: Codable, Hashable {
    let x: Double
    let y: Double
    let r: Double
    let color: String
}

/// One pile of chips the counting service found in a photo taken from the side.
/// Centre and size are fractions of the photo's width; `angle` follows OpenCV
/// (positive turns a box counter-clockwise), so SwiftUI draws it turned by `-angle`.
struct StackDetection: Codable, Hashable {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let angle: Double
    let color: String
    let count: Int
    let confidence: String
}

/// Response from POST /v1/sessions/{id}/photo — the backend's best-effort read of
/// the photo. `confidence` reflects how many chip candidates were ambiguous or
/// overlapping; the review screen always requires the user to confirm regardless.
struct ChipDetectionResult: Codable, Hashable {
    let counts: [String: Int]
    let confidence: String
    let photoUrl: String
    /// Where each counted chip is. Empty from a server that predates it.
    let detections: [ChipDetection]
    /// For a photo read from the side: each pile and how many chips it holds.
    let stacks: [StackDetection]
    /// "top" (a circle per chip) or "side" (a pile at a time). A server that predates
    /// side-view counting only ever answers "top".
    let view: String

    init(
        counts: [String: Int], confidence: String, photoUrl: String,
        detections: [ChipDetection] = [], stacks: [StackDetection] = [], view: String = "top"
    ) {
        self.counts = counts
        self.confidence = confidence
        self.photoUrl = photoUrl
        self.detections = detections
        self.stacks = stacks
        self.view = view
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        counts = try container.decode([String: Int].self, forKey: .counts)
        confidence = try container.decode(String.self, forKey: .confidence)
        photoUrl = try container.decode(String.self, forKey: .photoUrl)
        // The circles are a convenience: a missing or malformed list must never cost anyone their counts.
        detections = (try? container.decodeIfPresent([ChipDetection].self, forKey: .detections)) ?? []
        stacks = (try? container.decodeIfPresent([StackDetection].self, forKey: .stacks)) ?? []
        view = (try? container.decodeIfPresent(String.self, forKey: .view)) ?? "top"
    }
}
