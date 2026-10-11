import Foundation

public enum EligibilityStatus: Int, Hashable, Sendable, Comparable {
    /// Can realistically play.
    case eligible = 0
    /// Exists and is open, but access rules probably exclude this user.
    case restricted
    /// Not playable right now (closed, blackout, unplayable surface, closure reports).
    case unavailable
    public static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }
}

public struct Eligibility: Hashable, Sendable {
    public var status: EligibilityStatus
    /// Primary human-readable reason when not eligible, e.g. "Tournament — public play unavailable until 6 PM".
    public var reason: String?
    public var until: Date?
    /// Soft warnings that don't exclude (unconfirmed closure report, damp courts, rain likely...).
    public var warnings: [String]
    /// What kind of issue it is, for map status icons.
    public var issue: FacilityIssue?

    public static let ok = Eligibility(status: .eligible, reason: nil, until: nil, warnings: [], issue: nil)
}

public enum FacilityIssue: String, Hashable, Sendable {
    case closedHours, blackout, closureReported, temporarilyClosed, surface, dark, accessRestricted, noCourts, permanentlyClosed
}

public struct EligibilityEvaluator: Sendable {
    /// Surface reports older than this are ignored.
    public var surfaceReportMaxAgeMinutes: Double = 180
    /// Negative override needs this confidence (or ≥2 reports) to exclude rather than warn.
    public var negativeOverrideExcludeConfidence: Double = 0.6

    public init() {}

    public func evaluate(_ f: Facility, now: Date, prefs: UserPreferences, weather: WeatherAssessment?,
                         usableCourts: Int?, timeFormatter: (Date) -> String = EligibilityEvaluator.defaultTime) -> Eligibility {
        var warnings: [String] = []

        if f.existenceStatus == .closed || f.existenceStatus == .rejected {
            return Eligibility(status: .unavailable, reason: "Confirmed closed", until: nil, warnings: [], issue: .permanentlyClosed)
        }

        // Blackouts: confirmed whole-facility blackouts override everything else.
        for b in f.blackouts where b.isActive(at: now) {
            if b.isConfirmed && b.courtsAffected == nil {
                let reason = "\(b.reason.displayName) — public play unavailable until \(timeFormatter(b.endAt))"
                return Eligibility(status: .unavailable, reason: reason, until: b.endAt, warnings: [], issue: .blackout)
            } else if !b.isConfirmed {
                warnings.append("\(b.reason.displayName) reported (unconfirmed)")
            }
        }

        // Negative operational reports propagate fast: credible → exclude, single → warn.
        let negatives = f.overrides.filter { $0.kind.isNegative && $0.isActive(at: now) }
        if let strongest = negatives.max(by: { $0.confidence < $1.confidence }) {
            let credible = strongest.verified || strongest.confidence >= negativeOverrideExcludeConfidence || strongest.reportCount >= 2
            if credible {
                let reason = strongest.reportCount >= 2 && !strongest.verified
                    ? "Multiple recent reports: \(strongest.kind.displayName.lowercased())"
                    : strongest.kind.displayName
                let issue: FacilityIssue = strongest.kind == .unsafeSurface ? .surface : .temporarilyClosed
                return Eligibility(status: .unavailable, reason: reason, until: strongest.expiresAt, warnings: warnings, issue: issue)
            }
            warnings.append(strongest.kind.displayName)
        }

        // Hours.
        if let openState = Self.openState(f, at: now), !openState.isOpen {
            let reason = openState.nextOpen.map { "Closed — opens \(timeFormatter($0))" } ?? "Closed now"
            return Eligibility(status: .unavailable, reason: reason, until: openState.nextOpen, warnings: warnings, issue: .closedHours)
        }

        // Daylight for unlit outdoor courts.
        if f.indoorOutdoor != .indoor, f.hasLights == false, weather?.isDark == true {
            return Eligibility(status: .unavailable, reason: "Dark — no court lights", until: nil, warnings: warnings, issue: .dark)
        }

        // Surface playability (recent direct observations beat forecasts).
        if let s = f.surface, s.ageMinutes <= surfaceReportMaxAgeMinutes {
            if s.condition.isUnplayable && s.confidence >= 0.4 {
                return Eligibility(status: .unavailable, reason: "Courts currently \(s.condition.displayName.lowercased())",
                                   until: nil, warnings: warnings, issue: .surface)
            }
            if s.condition.isDegraded { warnings.append("Surface: \(s.condition.displayName.lowercased())") }
        } else if let w = weather, f.indoorOutdoor != .indoor, w.rainLikely || w.recentRain {
            warnings.append(w.rainLikely ? "Rain likely — courts may be wet" : "Recent rain — courts may be damp")
        }

        if let usable = usableCourts, usable == 0 {
            return Eligibility(status: .unavailable, reason: "No courts set up for pickleball right now",
                               until: nil, warnings: warnings, issue: .noCourts)
        }

        // Access.
        if !f.access.accessType.isOpenToOrdinaryPlayers && !prefs.accessGrantedFacilityIDs.contains(f.id) {
            let reason = f.access.accessNotes?.isEmpty == false ? f.access.accessNotes! : f.access.accessType.displayName
            return Eligibility(status: .restricted, reason: reason, until: nil, warnings: warnings, issue: .accessRestricted)
        }
        if f.access.permitRequired == true { warnings.append("Permit required") }
        if f.access.reservationRequired == true { warnings.append("Reservation required") }

        return Eligibility(status: .eligible, reason: nil, until: nil, warnings: warnings, issue: nil)
    }

    public struct OpenState: Hashable, Sendable { public var isOpen: Bool; public var nextOpen: Date?; public var closesAt: Date? }

    /// nil when hours are unknown.
    public static func openState(_ f: Facility, at now: Date) -> OpenState? {
        guard !f.hours.isEmpty else { return nil }
        let tz = f.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let (dow, _) = TimeBuckets.bucket(for: now, timeZone: tz)
        let minute = TimeBuckets.minuteOfDay(for: now, timeZone: tz)
        let dayStart = cal.startOfDay(for: now)
        for h in f.hours where h.dayOfWeek == dow {
            if let o = h.opensMinutes, let c = h.closesMinutes, minute >= o, minute < c {
                return OpenState(isOpen: true, nextOpen: nil, closesAt: cal.date(byAdding: .minute, value: c, to: dayStart))
            }
        }
        // Find the next opening within 7 days.
        for offset in 0..<8 {
            let d = (dow + offset) % 7
            let opens = f.hours.filter { $0.dayOfWeek == d }.compactMap(\.opensMinutes).sorted()
            for o in opens where offset > 0 || o > minute {
                if let day = cal.date(byAdding: .day, value: offset, to: dayStart) {
                    return OpenState(isOpen: false, nextOpen: cal.date(byAdding: .minute, value: o, to: day), closesAt: nil)
                }
            }
        }
        return OpenState(isOpen: false, nextOpen: nil, closesAt: nil)
    }

    public static func defaultTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        let s = f.string(from: date)
        return s.replacingOccurrences(of: ":00", with: "")
    }
}
