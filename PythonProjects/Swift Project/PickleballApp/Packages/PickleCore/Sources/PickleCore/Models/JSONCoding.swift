import Foundation

/// Shared JSON configuration matching the Postgres/PostgREST wire format.
public enum JSONCoding {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = parseDate(s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognised date: \(s)")
        }
        return d
    }()

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(isoFormatter.string(from: date))
        }
        return e
    }()

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Accepts ISO-8601 with/without fractional seconds and Postgres' "2024-05-01 10:00:00+00".
    public static func parseDate(_ raw: String) -> Date? {
        var s = raw.replacingOccurrences(of: " ", with: "T")
        if s.hasSuffix("+00") { s += ":00" }
        if let d = isoFormatter.date(from: s) ?? isoNoFraction.date(from: s) { return d }
        // Postgres can emit up to 6 fractional digits; trim to 3.
        if let dot = s.firstIndex(of: "."), let tz = s[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let frac = s[s.index(after: dot)..<tz].prefix(3)
            s = String(s[..<dot]) + "." + frac + String(s[tz...])
            return isoFormatter.date(from: s)
        }
        return nil
    }
}
