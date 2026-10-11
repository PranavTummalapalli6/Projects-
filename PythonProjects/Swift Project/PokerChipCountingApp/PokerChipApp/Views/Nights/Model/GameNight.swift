//
//  GameNight.swift
//  PokerChipApp
//
//  A home game, start to finish: who played, what each put in and took out, and
//  the clock. Money is whole minor units (cents) throughout — nothing in this
//  layer touches floating point — so every total reconciles to the cent.
//

import Foundation

struct Blinds: Codable, Hashable {
    var smallMinor: Int
    var bigMinor: Int
}

/// One buy-in or rebuy. Each is its own event, so a rebuy can be undone and the
/// night's history stays complete.
struct BuyInEvent: Codable, Hashable, Identifiable {
    var id: UUID
    var amountMinor: Int
    var at: Date
}

struct PlayerLedger: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var buyIns: [BuyInEvent]
    var cashOutMinor: Int?
    var cashedOutAt: Date?

    var totalInMinor: Int { buyIns.reduce(0) { $0 + $1.amountMinor } }
    var rebuyCount: Int { max(0, buyIns.count - 1) }
    var isCashedOut: Bool { cashOutMinor != nil }

    /// What they left with minus what they put in; nil until they cash out.
    var netMinor: Int? { cashOutMinor.map { $0 - totalInMinor } }
}

/// A stretch when the game was on hold; it doesn't count as playtime.
struct PauseInterval: Codable, Hashable {
    var start: Date
    var end: Date?
}

/// How a mismatch between the money in and the chips cashed out was settled.
/// It records the amount it was made for, so it stops applying — and the night
/// asks again — if a cash-out is corrected afterwards.
struct BankResolution: Codable, Hashable {
    enum Kind: String, Codable {
        /// The shortfall was a tip or a rake; the house keeps it.
        case tip
        /// The whole difference is put on one player.
        case assign
        /// The difference is shared out evenly, cent by cent.
        case split
    }

    var kind: Kind
    var playerID: UUID?
    /// Σ cash-outs − Σ buy-ins at the time of the choice.
    var deltaMinor: Int
}

struct GameNight: Codable, Hashable, Identifiable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var startedAt: Date
    /// When play stopped. Nil while the game is on.
    var endedAt: Date?
    /// When the night was reconciled and closed. Nil until then.
    var settledAt: Date?
    var tzIdentifier: String
    var currency: String
    var defaultBuyInMinor: Int
    var blinds: Blinds?
    var location: String?
    var notes: String?
    /// Chip colours in use, in table order (White → Black).
    var colors: [String]
    var denominationsMinor: [String: Int]
    /// The stack each player started with, by colour.
    var startingCounts: [String: Int]?
    var players: [PlayerLedger]
    /// Which player is the person holding this phone — what their stats and
    /// "your result" are about. Nil if they weren't playing.
    var myPlayerID: UUID?
    var pauses: [PauseInterval]
    var resolution: BankResolution?
    /// A logical clock for last-writer-wins merging between devices.
    var updatedAt: Date
    /// Set when the night is deleted; the record stays until every device has heard.
    var deletedAt: Date?
    /// "legacy-session" for nights imported from the single-player era.
    var source: String?

    init(
        schemaVersion: Int = GameNight.currentSchemaVersion,
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        settledAt: Date? = nil,
        tzIdentifier: String,
        currency: String = Money.defaultCurrencyCode,
        defaultBuyInMinor: Int,
        blinds: Blinds? = nil,
        location: String? = nil,
        notes: String? = nil,
        colors: [String],
        denominationsMinor: [String: Int],
        startingCounts: [String: Int]? = nil,
        players: [PlayerLedger],
        myPlayerID: UUID? = nil,
        pauses: [PauseInterval] = [],
        resolution: BankResolution? = nil,
        updatedAt: Date,
        deletedAt: Date? = nil,
        source: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.settledAt = settledAt
        self.tzIdentifier = tzIdentifier
        self.currency = currency
        self.defaultBuyInMinor = defaultBuyInMinor
        self.blinds = blinds
        self.location = location
        self.notes = notes
        self.colors = colors
        self.denominationsMinor = denominationsMinor
        self.startingCounts = startingCounts
        self.players = players
        self.myPlayerID = myPlayerID
        self.pauses = pauses
        self.resolution = resolution
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.source = source
    }

    // MARK: Decoding

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, startedAt, endedAt, settledAt, tzIdentifier, currency, defaultBuyInMinor
        case blinds, location, notes, colors, denominationsMinor, startingCounts, players, myPlayerID, pauses
        case resolution, updatedAt, deletedAt, source
    }

    /// Fields added after the first release decode to a sensible default, so a
    /// night saved by an older build still opens.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? GameNight.currentSchemaVersion
        id = try c.decode(UUID.self, forKey: .id)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        settledAt = try c.decodeIfPresent(Date.self, forKey: .settledAt)
        tzIdentifier = try c.decodeIfPresent(String.self, forKey: .tzIdentifier) ?? TimeZone.current.identifier
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? Money.defaultCurrencyCode
        defaultBuyInMinor = try c.decodeIfPresent(Int.self, forKey: .defaultBuyInMinor) ?? 0
        blinds = try c.decodeIfPresent(Blinds.self, forKey: .blinds)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        colors = try c.decodeIfPresent([String].self, forKey: .colors) ?? []
        denominationsMinor = try c.decodeIfPresent([String: Int].self, forKey: .denominationsMinor) ?? [:]
        startingCounts = try c.decodeIfPresent([String: Int].self, forKey: .startingCounts)
        players = try c.decode([PlayerLedger].self, forKey: .players)
        myPlayerID = try c.decodeIfPresent(UUID.self, forKey: .myPlayerID)
        pauses = try c.decodeIfPresent([PauseInterval].self, forKey: .pauses) ?? []
        resolution = try c.decodeIfPresent(BankResolution.self, forKey: .resolution)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? startedAt
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        source = try c.decodeIfPresent(String.self, forKey: .source)
    }
}

// MARK: - Starting a night

extension GameNight {
    /// A new night with every player in for the default buy-in.
    static func start(
        id: UUID = UUID(),
        now: Date = Date(),
        timeZone: TimeZone = .current,
        currency: String = Money.defaultCurrencyCode,
        buyInMinor: Int,
        playerNames: [String],
        colors: [String],
        denominationsMinor: [String: Int],
        startingCounts: [String: Int]? = nil,
        blinds: Blinds? = nil,
        location: String? = nil,
        myPlayerIndex: Int? = 0
    ) -> GameNight {
        let players = playerNames.enumerated().map { index, raw in
            PlayerLedger(
                id: UUID(),
                name: PlayerNaming.clean(raw, fallbackNumber: index + 1),
                buyIns: [BuyInEvent(id: UUID(), amountMinor: buyInMinor, at: now)],
                cashOutMinor: nil,
                cashedOutAt: nil
            )
        }
        return GameNight(
            id: id,
            startedAt: now,
            tzIdentifier: timeZone.identifier,
            currency: currency,
            defaultBuyInMinor: buyInMinor,
            blinds: blinds,
            location: PlayerNaming.trimmedOrNil(location),
            colors: colors,
            denominationsMinor: denominationsMinor,
            startingCounts: startingCounts,
            players: players,
            myPlayerID: myPlayerIndex.flatMap { players.indices.contains($0) ? players[$0].id : nil },
            updatedAt: now
        )
    }
}

enum PlayerNaming {
    /// A trimmed name, or "Player N" if nothing usable was typed.
    static func clean(_ raw: String, fallbackNumber: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Player \(fallbackNumber)" : String(trimmed.prefix(40))
    }

    static func trimmedOrNil(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(80))
    }

    /// Notes are tidied the same way, with room for a few paragraphs.
    static func notesOrNil(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(2_000))
    }
}

// MARK: - Regulars

/// People and places from earlier nights, offered as quick picks when setting
/// up a new one.
enum Regulars {
    /// Names that have played before — most often first, then most recent —
    /// spelled the way they were last typed. The "Player 3" names given to
    /// people who weren't named don't count.
    static func names(from nights: [GameNight]) -> [String] {
        var tally: [String: (count: Int, last: Date, spelling: String)] = [:]
        for night in nights where !night.isDeleted {
            for player in night.players where !isPlaceholder(player.name) {
                let key = player.name.lowercased()
                if var entry = tally[key] {
                    entry.count += 1
                    if night.startedAt >= entry.last { entry.last = night.startedAt; entry.spelling = player.name }
                    tally[key] = entry
                } else {
                    tally[key] = (1, night.startedAt, player.name)
                }
            }
        }
        return tally.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : ($0.last != $1.last ? $0.last > $1.last : $0.spelling < $1.spelling) }
            .map(\.spelling)
    }

    /// Places played at, most recent first.
    static func places(from nights: [GameNight]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for night in nights.filter({ !$0.isDeleted }).sorted(by: { $0.startedAt > $1.startedAt }) {
            guard let place = night.location, seen.insert(place.lowercased()).inserted else { continue }
            result.append(place)
        }
        return result
    }

    /// The candidates that start with what has been typed so far (all of them
    /// if nothing has), leaving out anyone already in this night.
    static func suggestions(from candidates: [String], matching typed: String, excluding used: [String], limit: Int = 6) -> [String] {
        let prefix = typed.trimmingCharacters(in: .whitespaces).lowercased()
        let taken = Set(used.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        return Array(
            candidates
                .filter { !taken.contains($0.lowercased()) && (prefix.isEmpty || $0.lowercased().hasPrefix(prefix)) }
                .prefix(limit)
        )
    }

    static func isPlaceholder(_ name: String) -> Bool {
        guard name.hasPrefix("Player ") else { return false }
        return Int(name.dropFirst("Player ".count)) != nil
    }
}
