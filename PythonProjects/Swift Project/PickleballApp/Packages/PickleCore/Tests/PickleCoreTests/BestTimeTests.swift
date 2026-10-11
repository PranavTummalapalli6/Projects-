import XCTest
@testable import PickleCore

final class BestTimeTests: XCTestCase {
    let planner = BestTimePlanner()

    func testFindsQuietWindowAfterEveningPeak() {
        let now = Fixtures.wednesdayEvening // 18:00 UTC Wednesday (dow 3)
        var buckets: [HistoricalBucket] = []
        for b in 36..<48 {
            let occ: Double = b < 39 ? 1.0 : (b < 42 ? 0.9 : 0.3) // busy until 21:00, quiet after
            buckets.append(HistoricalBucket(dayOfWeek: 3, bucket: b, sampleCount: 20, avgOccupancy: occ))
        }
        let f = Fixtures.facility(hours: [FacilityHours(dayOfWeek: 3, opens: "07:00", closes: "23:00")])
        let result = planner.plan(facility: f, now: now, weekBuckets: buckets, current: nil, weather: nil)
        XCTAssertTrue(result.basedOnHistory)
        XCTAssertEqual(result.slots.first?.level, .veryBusy)
        let startBucket = TimeBuckets.bucket(for: result.bestStart!, timeZone: Fixtures.utc).bucket
        XCTAssertEqual(startBucket, 42) // 21:00
        XCTAssertTrue(result.slots.allSatisfy { TimeBuckets.minuteOfDay(for: $0.start, timeZone: Fixtures.utc) < 23 * 60 })
    }

    func testBlackoutSlotsUnavailable() {
        let now = Fixtures.wednesdayEvening
        var f = Fixtures.facility()
        f.blackouts = [Blackout(startAt: now, endAt: now.addingTimeInterval(2 * 3600), reason: .tournament)]
        let result = planner.plan(facility: f, now: now, weekBuckets: [], current: nil, weather: nil)
        XCTAssertEqual(result.slots.prefix(4).map(\.level), Array(repeating: .unavailable, count: 4))
        XCTAssertGreaterThanOrEqual(result.bestStart!, now.addingTimeInterval(2 * 3600))
    }

    func testDarkUnlitCourtsUnavailable() {
        let now = Fixtures.wednesdayEvening
        var f = Fixtures.facility()
        f.hasLights = false
        let hourly = (0..<5).map { HourlyWeather(date: now.addingTimeInterval(Double($0) * 3600), temperatureF: 65, windMph: 3, isDaylight: $0 < 1) }
        let result = planner.plan(facility: f, now: now, weekBuckets: [], current: nil,
                                  weather: WeatherConditions(temperatureF: 65, windMph: 3, hourly: hourly))
        XCTAssertEqual(result.slots.first { $0.start >= now.addingTimeInterval(7200) }?.level, .unavailable)
    }
}
