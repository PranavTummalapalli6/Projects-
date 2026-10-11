import Foundation

/// Generic population prior used only when a facility has no history of its own.
/// Shape: quiet early mornings, a morning bump (retirees/open play), lunch dip, evening peak on weekdays;
/// weekends busy from mid-morning to mid-afternoon. Always reported as low confidence.
public enum OccupancyPrior {
    public static func occupancy(dayOfWeek: Int, bucket: Int, indoor: Bool) -> Double {
        let hour = Double(bucket) / 2.0
        let weekend = dayOfWeek == 0 || dayOfWeek == 6
        func bump(_ center: Double, _ width: Double, _ height: Double) -> Double {
            height * exp(-pow(hour - center, 2) / (2 * width * width))
        }
        var value: Double
        if weekend {
            value = 0.1 + bump(10.5, 2.2, 0.6) + bump(15, 2, 0.35) + bump(18.5, 1.5, 0.2)
        } else {
            value = 0.08 + bump(9, 1.5, 0.45) + bump(12.5, 1, 0.1) + bump(18.5, 1.6, 0.7)
        }
        if hour < 6 || hour >= 22 { value = 0.03 }
        if indoor { value = min(1, value * 1.1) }
        return min(1, max(0, value))
    }
}

public enum TimeBuckets {
    /// 30-minute bucket index (0...47) and Postgres-style weekday (0 = Sunday) in the given time zone.
    public static func bucket(for date: Date, timeZone: TimeZone = .current) -> (dayOfWeek: Int, bucket: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        let dow = (c.weekday ?? 1) - 1
        let bucket = (c.hour ?? 0) * 2 + ((c.minute ?? 0) >= 30 ? 1 : 0)
        return (dow, bucket)
    }

    public static func minuteOfDay(for date: Date, timeZone: TimeZone = .current) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
