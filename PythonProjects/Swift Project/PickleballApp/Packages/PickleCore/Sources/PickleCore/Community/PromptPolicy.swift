import Foundation

/// The single, context-chosen question we may ask at a facility.
public enum PromptKind: String, Codable, Hashable, Sendable, CaseIterable {
    case howBusy = "how_busy"
    case paddleWait = "paddle_wait"
    case courtSurface = "court_surface"
    case confirmExists = "confirm_exists"
}

public struct PromptPolicyConfig: Codable, Hashable, Sendable {
    public var sameFacilityCooldown: TimeInterval = 3 * 3600
    public var minGapBetweenPrompts: TimeInterval = 20 * 60
    public var freshHighConfidenceWindowMinutes: Double = 15
    public var freshSurfaceWindowMinutes: Double = 90
    public var shortBackoffAfterDismissals = 2
    public var shortBackoff: TimeInterval = 3 * 86400
    public var longBackoffAfterDismissals = 4
    public var longBackoff: TimeInterval = 14 * 86400
    public init() {}
}

public struct FacilityPromptState: Codable, Hashable, Sendable {
    public var lastPromptedAt: Date?
    public var lastReportedAt: Date?
    public var lastPromptVisitID: UUID?
    public var confirmedExistence = false
    public init() {}
}

/// Persisted locally (and mirrored to `report_prompt_state` server-side for cross-device later).
public struct PromptState: Codable, Hashable, Sendable {
    public var facilities: [UUID: FacilityPromptState] = [:]
    public var lastPromptAt: Date?
    public var consecutiveDismissals = 0
    public var backoffUntil: Date?
    public init() {}
}

public enum PromptDecision: Hashable, Sendable {
    case ask(PromptKind)
    case skip(String)

    public var kind: PromptKind? { if case .ask(let k) = self { k } else { nil } }
}

public struct PromptContext: Sendable {
    public var facility: Facility
    public var visitID: UUID
    public var isNearby: Bool
    public var prediction: WaitPrediction?
    public var weather: WeatherAssessment?
    public var now: Date

    public init(facility: Facility, visitID: UUID, isNearby: Bool, prediction: WaitPrediction?,
                weather: WeatherAssessment?, now: Date) {
        self.facility = facility; self.visitID = visitID; self.isNearby = isNearby
        self.prediction = prediction; self.weather = weather; self.now = now
    }
}

/// Central prompt-frequency policy: infer first → ask only when needed → one simple question.
public struct PromptPolicy: Sendable {
    public var config: PromptPolicyConfig
    public init(config: PromptPolicyConfig = .init()) { self.config = config }

    /// Which single question is most useful here, if any.
    public func chooseKind(_ ctx: PromptContext, state: FacilityPromptState) -> PromptKind? {
        let f = ctx.facility
        if f.isCommunityReported && !state.confirmedExistence { return .confirmExists }
        let surfaceFresh = (f.surface?.ageMinutes ?? .infinity) <= config.freshSurfaceWindowMinutes
        if f.indoorOutdoor != .indoor, !surfaceFresh, let w = ctx.weather, w.recentRain || w.rainLikely {
            return .courtSurface
        }
        let liveFresh = (ctx.prediction?.newestLiveAgeMinutes ?? .infinity) <= config.freshHighConfidenceWindowMinutes
        if liveFresh && ctx.prediction?.confidence == .high { return nil }
        return f.playSystem.isRotation ? .paddleWait : .howBusy
    }

    public func decide(_ ctx: PromptContext, state: PromptState) -> PromptDecision {
        guard ctx.isNearby else { return .skip("not at facility") }
        if let until = state.backoffUntil, ctx.now < until { return .skip("backing off after dismissals") }
        if let last = state.lastPromptAt, ctx.now.timeIntervalSince(last) < config.minGapBetweenPrompts {
            return .skip("prompted recently")
        }
        let fs = state.facilities[ctx.facility.id] ?? FacilityPromptState()
        if fs.lastPromptVisitID == ctx.visitID { return .skip("already asked this visit") }
        if let r = fs.lastReportedAt, ctx.now.timeIntervalSince(r) < config.sameFacilityCooldown {
            return .skip("reported here recently")
        }
        if let p = fs.lastPromptedAt, ctx.now.timeIntervalSince(p) < config.sameFacilityCooldown {
            return .skip("asked here recently")
        }
        guard let kind = chooseKind(ctx, state: fs) else { return .skip("fresh high-confidence data exists") }
        return .ask(kind)
    }

    public func recordShown(_ state: inout PromptState, facilityID: UUID, visitID: UUID, at now: Date) {
        state.lastPromptAt = now
        state.facilities[facilityID, default: .init()].lastPromptedAt = now
        state.facilities[facilityID, default: .init()].lastPromptVisitID = visitID
    }

    public func recordDismissed(_ state: inout PromptState, at now: Date) {
        state.consecutiveDismissals += 1
        if state.consecutiveDismissals >= config.longBackoffAfterDismissals {
            state.backoffUntil = now.addingTimeInterval(config.longBackoff)
        } else if state.consecutiveDismissals >= config.shortBackoffAfterDismissals {
            state.backoffUntil = now.addingTimeInterval(config.shortBackoff)
        }
    }

    /// Any answer — prompted or voluntary — resets dismissal backoff.
    public func recordAnswered(_ state: inout PromptState, facilityID: UUID, kind: PromptKind, at now: Date) {
        state.consecutiveDismissals = 0
        state.backoffUntil = nil
        state.facilities[facilityID, default: .init()].lastReportedAt = now
        if kind == .confirmExists { state.facilities[facilityID, default: .init()].confirmedExistence = true }
    }
}
