import Foundation

public enum SlotLevel: String, Hashable, Sendable, Codable {
    case good, moderate, busy, veryBusy = "very_busy", poorWeather = "poor_weather", unavailable

    public var displayName: String {
        switch self {
        case .good: "Good"
        case .moderate: "Moderate"
        case .busy: "Busy"
        case .veryBusy: "Very busy"
        case .poorWeather: "Poor weather"
        case .unavailable: "Unavailable"
        }
    }
    public var isPlayable: Bool { self != .unavailable }
}

public struct TimeSlot: Hashable, Sendable, Identifiable {
    public var start: Date
    public var end: Date
    public var occupancy: Double
    public var level: SlotLevel
    public var note: String?
    /// Lower is better.
    public var score: Double
    public var id: Date { start }
}

public struct BestTimeResult: Hashable, Sendable {
    public var slots: [TimeSlot]
    public var bestStart: Date?
    public var bestEnd: Date?
    public var basedOnHistory: Bool
}

/// Upcoming-occupancy timeline for the rest of a day (docs §11 / Phase 11).
public struct BestTimePlanner: Sendable {
    public var config: PredictionConfig
    public init(config: PredictionConfig = .default) { self.config = config }

    /// - Parameters:
    ///   - weekBuckets: facility history (any days; matching weekday is used).
    ///   - current: the live prediction; its influence fades over ~90 minutes.
    public func plan(facility: Facility, now: Date, weekBuckets: [HistoricalBucket],
                     current: WaitPrediction?, weather: WeatherConditions?, minimumWindowSlots: Int = 2) -> BestTimeResult {
        let tz = facility.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let (dow, startBucket) = TimeBuckets.bucket(for: now, timeZone: tz)
        let dayStart = cal.startOfDay(for: now)
        let todaysHours = facility.hours.filter { $0.dayOfWeek == dow }
        let isOutdoor = facility.indoorOutdoor != .indoor
        let byBucket = Dictionary(weekBuckets.filter { $0.dayOfWeek == dow }.map { ($0.bucket, $0) }, uniquingKeysWith: { a, _ in a })
        let hasHistory = byBucket.values.contains { $0.sampleCount >= 3 }

        var slots: [TimeSlot] = []
        for b in startBucket..<48 {
            guard let start = cal.date(byAdding: .minute, value: b * 30, to: dayStart),
                  let end = cal.date(byAdding: .minute, value: 30, to: start) else { continue }
            let minute = b * 30

            if !todaysHours.isEmpty, !todaysHours.contains(where: { h in
                guard let o = h.opensMinutes, let c = h.closesMinutes else { return false }
                return minute >= o && minute + 30 <= max(c, o)
            }) { continue }
            if todaysHours.isEmpty && (minute < 6 * 60 || minute >= 22 * 60) { continue }

            var occ: Double
            if let h = byBucket[b], h.sampleCount > 0 {
                occ = h.avgOccupancy
            } else {
                occ = OccupancyPrior.occupancy(dayOfWeek: dow, bucket: b, indoor: !isOutdoor)
            }
            if let current {
                let minutesAhead = start.timeIntervalSince(now) / 60
                let liveInfluence = max(0, 1 - max(0, minutesAhead) / 90)
                occ = occ * (1 - liveInfluence) + current.occupancy * liveInfluence
            }

            var level: SlotLevel
            var note: String?
            var score = occ
            if let blackout = facility.blackouts.first(where: { $0.isConfirmed && $0.courtsAffected == nil && $0.startAt < end && $0.endAt > start }) {
                level = .unavailable; note = blackout.reason.displayName; score = 10
            } else {
                switch occ {
                case ..<0.6: level = .good
                case ..<0.85: level = .moderate
                case ..<1.0: level = .busy
                default: level = .veryBusy
                }
                if isOutdoor, let hour = Self.hourly(weather, at: start) {
                    let (wind, _) = WeatherAssessor.windCategory(windMph: hour.windMph, gustMph: hour.gustMph, thresholds: config.wind)
                    if !hour.isDaylight && facility.hasLights != true {
                        level = .unavailable; note = "Dark — no court lights"; score = 10
                    } else if hour.precipitationChance >= 0.6 {
                        level = .poorWeather; note = "Rain likely"; score += 0.8
                    } else if wind == .veryWindy {
                        level = .poorWeather; note = "Very windy"; score += 0.4
                    } else if wind == .windy {
                        note = "Windy"; score += 0.15
                    }
                }
            }
            slots.append(TimeSlot(start: start, end: end, occupancy: occ, level: level, note: note, score: score))
        }

        // Best contiguous playable window of at least `minimumWindowSlots`.
        var best: (start: Int, end: Int, avg: Double)?
        var i = 0
        while i < slots.count {
            guard slots[i].level.isPlayable else { i += 1; continue }
            var j = i
            while j + 1 < slots.count, slots[j + 1].level.isPlayable, slots[j + 1].start == slots[j].end { j += 1 }
            // Slide a window across this run.
            let run = Array(i...j)
            if run.count >= minimumWindowSlots {
                for s in run.indices {
                    for e in (s + minimumWindowSlots - 1)..<min(run.count, s + 6) {
                        let window = run[s...e]
                        let avg = window.reduce(0) { $0 + slots[$1].score } / Double(window.count)
                        // Prefer lower score; on near-ties prefer earlier then longer windows.
                        if best == nil || avg < best!.avg - 0.05 ||
                            (abs(avg - best!.avg) <= 0.05 && run[s] == best!.start && run[e] > best!.end) {
                            best = (run[s], run[e], avg)
                        }
                    }
                }
            }
            i = j + 1
        }
        return BestTimeResult(slots: slots,
                              bestStart: best.map { slots[$0.start].start },
                              bestEnd: best.map { slots[$0.end].end },
                              basedOnHistory: hasHistory)
    }

    static func hourly(_ w: WeatherConditions?, at date: Date) -> HourlyWeather? {
        guard let w, !w.hourly.isEmpty else { return nil }
        return w.hourly.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
            .flatMap { abs($0.date.timeIntervalSince(date)) <= 3600 ? $0 : nil }
    }
}
