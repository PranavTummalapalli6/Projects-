import Foundation
import PickleCore

enum Format {
    static func minutes(_ m: Double) -> String {
        let v = Int(m.rounded())
        if v < 60 { return "\(max(1, v)) min" }
        let h = v / 60, r = v % 60
        return r == 0 ? "\(h) hr" : "\(h) hr \(r) min"
    }

    static func travel(_ t: TravelEstimate?) -> String? {
        guard let t else { return nil }
        let base = minutes(t.minutes)
        return t.isEstimate ? "~\(base) away" : "\(base) drive"
    }

    static func distance(_ meters: Double) -> String {
        let miles = meters / 1609.34
        return miles < 0.2 ? "\(Int((meters * 3.281 / 50).rounded() * 50)) ft" : String(format: miles < 10 ? "%.1f mi" : "%.0f mi", miles)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened).replacingOccurrences(of: ":00", with: "")
    }

    static func timeRange(_ a: Date, _ b: Date) -> String { "\(time(a))–\(time(b))" }

    static func age(minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m < 1 { return "just now" }
        if m < 60 { return "\(m) min ago" }
        return "\(m / 60) hr ago"
    }

    static func money(_ v: Double) -> String {
        v.rounded() == v ? String(format: "$%.0f", v) : String(format: "$%.2f", v)
    }

    static func relativeDays(until date: Date) -> String {
        let days = Int(ceil(date.timeIntervalSinceNow / 86400))
        return days <= 1 ? "today" : "for the next \(days) days"
    }
}
