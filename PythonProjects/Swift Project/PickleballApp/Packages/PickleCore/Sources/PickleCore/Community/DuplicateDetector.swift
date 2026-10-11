import Foundation

public struct DuplicateCandidate: Hashable, Sendable, Identifiable {
    public var facilityID: UUID
    public var name: String
    public var distanceMeters: Double
    public var nameSimilarity: Double
    public var score: Double
    public var id: UUID { facilityID }
}

/// Client-side mirror of the server's duplicate rules (server is authoritative; see
/// `find_duplicate_facilities` in the migrations). Used to show "Is this one of these?" instantly.
public struct DuplicateDetector: Sendable {
    public var sameSpotMeters = 60.0
    public var nearbyMeters = 250.0
    public var nearbyNameThreshold = 0.6
    public var wideMeters = 400.0
    public var wideNameThreshold = 0.85

    public init() {}

    public func candidates(name: String?, location: GeoPoint,
                           existing: [(id: UUID, name: String, location: GeoPoint, address: String?)],
                           address: String? = nil) -> [DuplicateCandidate] {
        existing.compactMap { e in
            let d = GeoMath.distanceMeters(location, e.location)
            guard d <= wideMeters else { return nil }
            let sim = name.map { Self.similarity($0, e.name) } ?? 0
            let addrMatch = address.flatMap { a in e.address.map { Self.normalize(a) == Self.normalize($0) } } ?? false
            let isDup = d <= sameSpotMeters
                || (d <= nearbyMeters && (sim >= nearbyNameThreshold || addrMatch || name == nil))
                || sim >= wideNameThreshold
            guard isDup else { return nil }
            let score = (1 - d / wideMeters) * 0.5 + sim * 0.5 + (addrMatch ? 0.2 : 0)
            return DuplicateCandidate(facilityID: e.id, name: e.name, distanceMeters: d, nameSimilarity: sim, score: score)
        }
        .sorted { $0.score > $1.score }
    }

    static let abbreviations: [String: String] = [
        "pk": "park", "ctr": "center", "cntr": "center", "centre": "center", "rec": "recreation",
        "st": "street", "ave": "avenue", "rd": "road", "hs": "high school", "ms": "middle school",
        "es": "elementary school", "comm": "community", "reg": "regional", "mt": "mount",
    ]
    /// Generic words that don't distinguish facilities.
    static let stopWords: Set<String> = ["the", "of", "at", "and", "courts", "court", "pickleball", "tennis", "facility", "complex"]

    public static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US"))
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(cleaned).split(separator: " ").map { abbreviations[String($0)] ?? String($0) }
            .filter { !stopWords.contains($0) }
            .joined(separator: " ")
    }

    /// Soft token Dice coefficient on normalized names, 0...1. Tokens match when their Jaro-Winkler
    /// similarity ≥ 0.88, so typos ("Hansen"/"Hanson") match but unrelated names don't.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let na = normalize(a), nb = normalize(b)
        if na.isEmpty || nb.isEmpty { return 0 }
        if na == nb { return 1 }
        let ta = Array(Set(na.split(separator: " ").map(String.init)))
        var tb = Array(Set(nb.split(separator: " ").map(String.init)))
        let total = ta.count + tb.count
        var matches = 0
        for token in ta {
            if let i = tb.indices.max(by: { jaroWinkler(token, tb[$0]) < jaroWinkler(token, tb[$1]) }),
               jaroWinkler(token, tb[i]) >= 0.88 {
                matches += 1
                tb.remove(at: i)
            }
        }
        return 2 * Double(matches) / Double(total)
    }

    public static func jaroWinkler(_ s1: String, _ s2: String) -> Double {
        let a = Array(s1), b = Array(s2)
        if a.isEmpty && b.isEmpty { return 1 }
        let matchDistance = max(a.count, b.count) / 2 - 1
        var aMatches = [Bool](repeating: false, count: a.count)
        var bMatches = [Bool](repeating: false, count: b.count)
        var matches = 0
        for i in a.indices {
            let start = max(0, i - matchDistance), end = min(i + matchDistance + 1, b.count)
            guard start < end else { continue }
            for j in start..<end where !bMatches[j] && a[i] == b[j] {
                aMatches[i] = true; bMatches[j] = true; matches += 1; break
            }
        }
        guard matches > 0 else { return 0 }
        var t = 0.0, k = 0
        for i in a.indices where aMatches[i] {
            while !bMatches[k] { k += 1 }
            if a[i] != b[k] { t += 0.5 }
            k += 1
        }
        let m = Double(matches)
        let jaro = (m / Double(a.count) + m / Double(b.count) + (m - t) / m) / 3
        var prefix = 0
        for (x, y) in zip(a, b).prefix(4) { if x == y { prefix += 1 } else { break } }
        return jaro + Double(prefix) * 0.1 * (1 - jaro)
    }
}
