//
//  GameSetup.swift
//  PokerChipApp
//

import Foundation

/// What was entered on the buy-in screen. Remembered so the next game starts
/// from the same buy-in, player count and chip colours.
struct GameSetup: Codable, Hashable {
    var buyIn: Double
    var players: Int
    /// Canonical chip-colour order (White → Black), never a Set — it has to
    /// be Hashable/Codable and stable for navigation.
    var colors: [String]
    /// Who is playing, in seat order; the first is the person holding the
    /// phone. Blank entries become "Player N".
    var playerNames: [String] = []
    var location: String?
    /// The physical set, when the person has said what they own.
    var inventory: ChipInventory?
    /// Chip values (cents) the person has fixed, by colour.
    var lockedValues: [String: Int] = [:]

    var availableColors: Set<String> { Set(colors) }

    init(
        buyIn: Double,
        players: Int,
        availableColors: Set<String>,
        playerNames: [String] = [],
        location: String? = nil,
        inventory: ChipInventory? = nil,
        lockedValues: [String: Int] = [:]
    ) {
        self.buyIn = buyIn
        self.players = players
        self.colors = allChipColors.filter { availableColors.contains($0) }
        self.playerNames = playerNames
        self.location = location
        self.inventory = inventory
        self.lockedValues = lockedValues
    }

    /// Setups saved before names existed decode with none.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        buyIn = try container.decode(Double.self, forKey: .buyIn)
        players = try container.decode(Int.self, forKey: .players)
        colors = try container.decode([String].self, forKey: .colors)
        playerNames = try container.decodeIfPresent([String].self, forKey: .playerNames) ?? []
        location = try container.decodeIfPresent(String.self, forKey: .location)
        inventory = try container.decodeIfPresent(ChipInventory.self, forKey: .inventory)
        lockedValues = try container.decodeIfPresent([String: Int].self, forKey: .lockedValues) ?? [:]
    }

    /// Exactly `players` names: the ones entered, then blanks (which the night
    /// turns into "Player N").
    var namesForTable: [String] {
        (0..<max(players, 0)).map { $0 < playerNames.count ? playerNames[$0] : "" }
    }

    /// The setup after taking one of the suggestions offered for a chip set that
    /// is too small for the table.
    func applying(_ alternative: ChipAlternative) -> GameSetup {
        var result = self
        switch alternative.kind {
        case .fewerPlayers(let count):
            result.players = count
            result.playerNames = Array(playerNames.prefix(count))
        case .lowerBuyIn(let cents):
            result.buyIn = Double(cents) / 100
        case .dropColor(let color):
            result.colors.removeAll { $0 == color }
            result.lockedValues[color] = nil
        }
        return result
    }
}
