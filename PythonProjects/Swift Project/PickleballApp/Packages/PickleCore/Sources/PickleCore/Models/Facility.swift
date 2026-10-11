import Foundation

/// The facility payload returned by `nearby_facilities` / `facility_detail`.
/// Stable facts, temporary operational state, community observations and historical signals
/// arrive together but stay in separate sub-structures so the UI can label each honestly.
public struct Facility: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var address: String?
    public var city: String?
    public var state: String?
    public var postalCode: String?
    public var timeZone: String?

    // Stable facts
    public var totalPhysicalCourts: Int?
    public var defaultPickleballCourts: Int?
    public var courtType: CourtType
    public var indoorOutdoor: IndoorOutdoor
    public var hasLights: Bool?
    public var hasRestrooms: Bool?
    public var hasWater: Bool?
    public var hasParking: Bool?
    public var playSystem: PlaySystem
    public var typicalGameMinutes: Double?
    public var source: String?
    public var existenceStatus: VerificationStatus
    public var existenceConfidence: Double
    public var access: FacilityAccess
    public var cost: FacilityCost
    public var hours: [FacilityHours]

    // Temporary operational state
    public var blackouts: [Blackout]
    public var overrides: [OperationalOverride]
    public var surface: SurfaceSummary?

    // Community-estimated player fit
    public var skill: SkillSummary?
    public var culture: [CultureSummary]

    // Signals for prediction
    public var historicalNow: HistoricalBucket?
    public var sessionStats: SessionStats?
    public var live: LiveSignals?

    public init(
        id: UUID = UUID(), name: String, latitude: Double, longitude: Double,
        address: String? = nil, city: String? = nil, state: String? = nil, postalCode: String? = nil,
        timeZone: String? = nil, totalPhysicalCourts: Int? = nil, defaultPickleballCourts: Int? = nil,
        courtType: CourtType = .unknown, indoorOutdoor: IndoorOutdoor = .outdoor,
        hasLights: Bool? = nil, hasRestrooms: Bool? = nil, hasWater: Bool? = nil, hasParking: Bool? = nil,
        playSystem: PlaySystem = .unknown, typicalGameMinutes: Double? = nil, source: String? = nil,
        existenceStatus: VerificationStatus = .verified, existenceConfidence: Double = 0.9,
        access: FacilityAccess = .init(), cost: FacilityCost = .init(), hours: [FacilityHours] = [],
        blackouts: [Blackout] = [], overrides: [OperationalOverride] = [], surface: SurfaceSummary? = nil,
        skill: SkillSummary? = nil, culture: [CultureSummary] = [], historicalNow: HistoricalBucket? = nil,
        sessionStats: SessionStats? = nil, live: LiveSignals? = nil
    ) {
        self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
        self.address = address; self.city = city; self.state = state; self.postalCode = postalCode
        self.timeZone = timeZone
        self.totalPhysicalCourts = totalPhysicalCourts; self.defaultPickleballCourts = defaultPickleballCourts
        self.courtType = courtType; self.indoorOutdoor = indoorOutdoor
        self.hasLights = hasLights; self.hasRestrooms = hasRestrooms; self.hasWater = hasWater; self.hasParking = hasParking
        self.playSystem = playSystem; self.typicalGameMinutes = typicalGameMinutes; self.source = source
        self.existenceStatus = existenceStatus; self.existenceConfidence = existenceConfidence
        self.access = access; self.cost = cost; self.hours = hours
        self.blackouts = blackouts; self.overrides = overrides; self.surface = surface
        self.skill = skill; self.culture = culture
        self.historicalNow = historicalNow; self.sessionStats = sessionStats; self.live = live
    }

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, address, city, state, postalCode, timeZone
        case totalPhysicalCourts, defaultPickleballCourts, courtType, indoorOutdoor
        case hasLights, hasRestrooms, hasWater, hasParking, playSystem, typicalGameMinutes, source
        case existenceStatus, existenceConfidence, access, cost, hours
        case blackouts, overrides, surface, skill, culture, historicalNow, sessionStats, live
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        postalCode = try c.decodeIfPresent(String.self, forKey: .postalCode)
        timeZone = try c.decodeIfPresent(String.self, forKey: .timeZone)
        totalPhysicalCourts = try c.decodeIfPresent(Int.self, forKey: .totalPhysicalCourts)
        defaultPickleballCourts = try c.decodeIfPresent(Int.self, forKey: .defaultPickleballCourts)
        courtType = try c.decodeIfPresent(CourtType.self, forKey: .courtType) ?? .unknown
        indoorOutdoor = try c.decodeIfPresent(IndoorOutdoor.self, forKey: .indoorOutdoor) ?? .unknown
        hasLights = try c.decodeIfPresent(Bool.self, forKey: .hasLights)
        hasRestrooms = try c.decodeIfPresent(Bool.self, forKey: .hasRestrooms)
        hasWater = try c.decodeIfPresent(Bool.self, forKey: .hasWater)
        hasParking = try c.decodeIfPresent(Bool.self, forKey: .hasParking)
        playSystem = try c.decodeIfPresent(PlaySystem.self, forKey: .playSystem) ?? .unknown
        typicalGameMinutes = try c.decodeIfPresent(Double.self, forKey: .typicalGameMinutes)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        existenceStatus = try c.decodeIfPresent(VerificationStatus.self, forKey: .existenceStatus) ?? .pending
        existenceConfidence = try c.decodeIfPresent(Double.self, forKey: .existenceConfidence) ?? 0
        access = try c.decodeIfPresent(FacilityAccess.self, forKey: .access) ?? .init()
        cost = try c.decodeIfPresent(FacilityCost.self, forKey: .cost) ?? .init()
        hours = try c.decodeIfPresent([FacilityHours].self, forKey: .hours) ?? []
        blackouts = try c.decodeIfPresent([Blackout].self, forKey: .blackouts) ?? []
        overrides = try c.decodeIfPresent([OperationalOverride].self, forKey: .overrides) ?? []
        surface = try c.decodeIfPresent(SurfaceSummary.self, forKey: .surface)
        skill = try c.decodeIfPresent(SkillSummary.self, forKey: .skill)
        culture = try c.decodeIfPresent([CultureSummary].self, forKey: .culture) ?? []
        historicalNow = try c.decodeIfPresent(HistoricalBucket.self, forKey: .historicalNow)
        sessionStats = try c.decodeIfPresent(SessionStats.self, forKey: .sessionStats)
        live = try c.decodeIfPresent(LiveSignals.self, forKey: .live)
    }

    public var coordinate: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }

    public var isCommunityReported: Bool {
        existenceStatus == .pending || existenceStatus == .communityReported || existenceStatus == .partiallyVerified
    }

    /// Short "Hanson Park, Fairfax" style locality line.
    public var localityLine: String? {
        [address, city].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ").nilIfEmpty
    }
}

public struct FacilityAccess: Codable, Hashable, Sendable {
    public var accessType: AccessType
    public var accessNotes: String?
    public var reservationRequired: Bool?
    public var reservationAvailable: Bool?
    public var permitRequired: Bool?
    public var verificationStatus: VerificationStatus
    public var confidence: Double
    public var lastVerifiedAt: Date?

    public init(accessType: AccessType = .unknown, accessNotes: String? = nil, reservationRequired: Bool? = nil,
                reservationAvailable: Bool? = nil, permitRequired: Bool? = nil,
                verificationStatus: VerificationStatus = .pending, confidence: Double = 0, lastVerifiedAt: Date? = nil) {
        self.accessType = accessType; self.accessNotes = accessNotes; self.reservationRequired = reservationRequired
        self.reservationAvailable = reservationAvailable; self.permitRequired = permitRequired
        self.verificationStatus = verificationStatus; self.confidence = confidence; self.lastVerifiedAt = lastVerifiedAt
    }
}

public struct FacilityCost: Codable, Hashable, Sendable {
    public var costType: AccessCostType
    public var dayPassPrice: Double?
    public var reservationFee: Double?
    public var pricingNotes: String?
    public var lastVerifiedAt: Date?

    public init(costType: AccessCostType = .unknown, dayPassPrice: Double? = nil, reservationFee: Double? = nil,
                pricingNotes: String? = nil, lastVerifiedAt: Date? = nil) {
        self.costType = costType; self.dayPassPrice = dayPassPrice; self.reservationFee = reservationFee
        self.pricingNotes = pricingNotes; self.lastVerifiedAt = lastVerifiedAt
    }

    /// Best estimate of what one visit costs, if known.
    public var estimatedVisitCost: Double? {
        switch costType {
        case .free: 0
        case .dayPass: dayPassPrice
        case .reservationFee: reservationFee
        case .paid: dayPassPrice ?? reservationFee
        case .membership, .unknown: nil
        }
    }
}

/// Weekly opening hours. `dayOfWeek` follows Postgres `extract(dow)`: 0 = Sunday.
public struct FacilityHours: Codable, Hashable, Sendable {
    public var dayOfWeek: Int
    public var opens: String   // "HH:mm"
    public var closes: String  // "HH:mm"; "24:00" allowed
    public var notes: String?

    public init(dayOfWeek: Int, opens: String, closes: String, notes: String? = nil) {
        self.dayOfWeek = dayOfWeek; self.opens = opens; self.closes = closes; self.notes = notes
    }

    public var opensMinutes: Int? { Self.minutes(opens) }
    public var closesMinutes: Int? { Self.minutes(closes) }

    static func minutes(_ s: String) -> Int? {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0...24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
}

public struct Blackout: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var startAt: Date
    public var endAt: Date
    public var reason: BlackoutReason
    public var description: String?
    public var verificationStatus: VerificationStatus
    public var confidence: Double
    /// nil = whole facility; otherwise number of courts removed from public play.
    public var courtsAffected: Int?

    public init(id: UUID = UUID(), startAt: Date, endAt: Date, reason: BlackoutReason, description: String? = nil,
                verificationStatus: VerificationStatus = .verified, confidence: Double = 0.9, courtsAffected: Int? = nil) {
        self.id = id; self.startAt = startAt; self.endAt = endAt; self.reason = reason; self.description = description
        self.verificationStatus = verificationStatus; self.confidence = confidence; self.courtsAffected = courtsAffected
    }

    public func isActive(at date: Date) -> Bool { startAt <= date && date < endAt }
    public var isConfirmed: Bool { verificationStatus == .verified || confidence >= 0.7 }
}

public struct OperationalOverride: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: OverrideKind
    public var value: Int?
    public var note: String?
    public var startsAt: Date
    public var expiresAt: Date
    public var reportCount: Int
    public var confidence: Double
    public var verified: Bool

    public init(id: UUID = UUID(), kind: OverrideKind, value: Int? = nil, note: String? = nil, startsAt: Date,
                expiresAt: Date, reportCount: Int = 1, confidence: Double = 0.5, verified: Bool = false) {
        self.id = id; self.kind = kind; self.value = value; self.note = note; self.startsAt = startsAt
        self.expiresAt = expiresAt; self.reportCount = reportCount; self.confidence = confidence; self.verified = verified
    }

    public func isActive(at date: Date) -> Bool { startsAt <= date && date < expiresAt }
}

public struct SurfaceSummary: Codable, Hashable, Sendable {
    public var condition: SurfaceCondition
    public var ageMinutes: Double
    public var reportCount: Int
    public var confidence: Double

    public init(condition: SurfaceCondition, ageMinutes: Double, reportCount: Int = 1, confidence: Double = 0.6) {
        self.condition = condition; self.ageMinutes = ageMinutes; self.reportCount = reportCount; self.confidence = confidence
    }
}

public struct SkillBandWeight: Codable, Hashable, Sendable {
    public var band: SkillBand
    public var weight: Double
    public init(band: SkillBand, weight: Double) { self.band = band; self.weight = weight }
}

/// Community-estimated skill distribution. Never presented as objective fact.
public struct SkillSummary: Codable, Hashable, Sendable {
    public var bands: [SkillBandWeight]
    public var observationCount: Int
    public var newestDaysAgo: Double?

    public init(bands: [SkillBandWeight], observationCount: Int, newestDaysAgo: Double? = nil) {
        self.bands = bands; self.observationCount = observationCount; self.newestDaysAgo = newestDaysAgo
    }

    /// Central ~70% of the weighted distribution, e.g. 3.0–4.0.
    public var typicalRange: (low: SkillBand, high: SkillBand)? {
        let valid = bands.filter { $0.band.ordinal != nil && $0.weight > 0 }.sorted { $0.band < $1.band }
        let total = valid.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        var acc = 0.0
        var low: SkillBand?
        var high: SkillBand?
        for item in valid {
            acc += item.weight
            if low == nil, acc / total >= 0.15 { low = item.band }
            if high == nil, acc / total >= 0.85 { high = item.band }
        }
        guard let l = low, let h = high else { return nil }
        return (l, h)
    }

    public var confidence: ConfidenceLevel {
        let recent = (newestDaysAgo ?? 999) <= 60
        if observationCount >= 20 && recent { return .high }
        if observationCount >= 6 && recent { return .medium }
        return .low
    }

    /// "3.0–4.0" style label derived from the typical range.
    public var typicalLabel: String? {
        guard let r = typicalRange else { return nil }
        if r.low == r.high { return r.low.displayName }
        let lowStart = r.low == .beginner ? "Beginner" : String(r.low.rawValue.prefix(3))
        let highEnd = r.high == .b45plus ? "4.5+" : String(r.high.rawValue.suffix(3))
        return "\(lowStart)–\(highEnd)"
    }
}

public struct CultureSummary: Codable, Hashable, Sendable {
    public var tag: PlayCultureTag
    public var share: Double
    public var observationCount: Int
    public init(tag: PlayCultureTag, share: Double, observationCount: Int) {
        self.tag = tag; self.share = share; self.observationCount = observationCount
    }
}

/// One 30-minute bucket of historical usage. `bucket` 0...47 from local midnight.
public struct HistoricalBucket: Codable, Hashable, Sendable {
    public var dayOfWeek: Int
    public var bucket: Int
    public var sampleCount: Int
    public var avgOccupancy: Double
    public var medianWaitMinutes: Double?
    public var variance: Double?

    public init(dayOfWeek: Int, bucket: Int, sampleCount: Int, avgOccupancy: Double,
                medianWaitMinutes: Double? = nil, variance: Double? = nil) {
        self.dayOfWeek = dayOfWeek; self.bucket = bucket; self.sampleCount = sampleCount
        self.avgOccupancy = avgOccupancy; self.medianWaitMinutes = medianWaitMinutes; self.variance = variance
    }
}

public struct SessionStats: Codable, Hashable, Sendable {
    public var medianMinutes: Double
    public var p25Minutes: Double
    public var p75Minutes: Double
    public var sampleCount: Int
    public init(medianMinutes: Double, p25Minutes: Double, p75Minutes: Double, sampleCount: Int) {
        self.medianMinutes = medianMinutes; self.p25Minutes = p25Minutes; self.p75Minutes = p75Minutes
        self.sampleCount = sampleCount
    }
    public static let `default` = SessionStats(medianMinutes: 60, p25Minutes: 40, p75Minutes: 90, sampleCount: 0)
}

public enum LiveObservationKind: String, ResilientEnum {
    case occupancy, paddleStack = "paddle_stack"
    case unknown
    public static let fallback = LiveObservationKind.unknown
}

/// An anonymised, server-weighted recent observation. No user ids, no reporter coordinates.
public struct LiveObservation: Codable, Hashable, Sendable {
    public var kind: LiveObservationKind
    public var ageMinutes: Double
    public var status: OccupancyStatus?
    public var occupiedCourts: Int?
    public var groupsWaiting: Int?
    public var paddles: Double?
    /// Server-computed trust (location verification × integrity), rounded. Read-only.
    public var weight: Double
    public var locationVerified: Bool

    public init(kind: LiveObservationKind = .occupancy, ageMinutes: Double, status: OccupancyStatus? = nil,
                occupiedCourts: Int? = nil, groupsWaiting: Int? = nil, paddles: Double? = nil,
                weight: Double = 1, locationVerified: Bool = true) {
        self.kind = kind; self.ageMinutes = ageMinutes; self.status = status; self.occupiedCourts = occupiedCourts
        self.groupsWaiting = groupsWaiting; self.paddles = paddles; self.weight = weight
        self.locationVerified = locationVerified
    }
}

public struct LiveSignals: Codable, Hashable, Sendable {
    public var observations: [LiveObservation]
    public init(observations: [LiveObservation]) { self.observations = observations }

    public var newestAgeMinutes: Double? { observations.map(\.ageMinutes).min() }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
