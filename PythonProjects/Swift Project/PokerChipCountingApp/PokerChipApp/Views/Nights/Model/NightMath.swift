//
//  NightMath.swift
//  PokerChipApp
//
//  What a night adds up to: totals, each player's net, the bank check, how a
//  mismatch is resolved, and the playtime. All integer cents; every function is
//  pure, so it can be tested exhaustively.
//

import Foundation

/// One line of the final reckoning. Positive means the table owes them.
struct NetEntry: Hashable {
    /// Nil for the house (tips or rake), which isn't a player.
    var id: UUID?
    var name: String
    var netMinor: Int
}

extension GameNight {
    // MARK: State

    var isDeleted: Bool { deletedAt != nil }
    var isSettled: Bool { settledAt != nil }
    /// Play hasn't been called yet: the clock is running or paused.
    var isLive: Bool { endedAt == nil && !isSettled && !isDeleted }
    /// Not deleted and not yet closed — the night the Resume banner points at.
    var isOpen: Bool { !isSettled && !isDeleted }
    var hasOpenPause: Bool { pauses.last.map { $0.end == nil } ?? false }

    // MARK: Totals

    var totalInMinor: Int { players.reduce(0) { $0 + $1.totalInMinor } }
    var totalOutMinor: Int { players.reduce(0) { $0 + ($1.cashOutMinor ?? 0) } }
    var allCashedOut: Bool { !players.isEmpty && players.allSatisfy(\.isCashedOut) }
    var cashedOutCount: Int { players.filter(\.isCashedOut).count }

    /// Σ cash-outs − Σ buy-ins. Zero means the bank balances. Only meaningful
    /// once everyone has cashed out.
    var bankDeltaMinor: Int { totalOutMinor - totalInMinor }

    /// Players, most money in first — the running board.
    var playersByInvested: [PlayerLedger] {
        players.sorted {
            if $0.totalInMinor != $1.totalInMinor { return $0.totalInMinor > $1.totalInMinor }
            return PlayerOrder.precedes($0.name, $0.id, $1.name, $1.id)
        }
    }

    // MARK: The bank check

    /// The resolution, if it still applies: it must have been made for today's
    /// difference, and be one that makes sense for it.
    var activeResolution: BankResolution? {
        let delta = bankDeltaMinor
        guard delta != 0, let resolution, resolution.deltaMinor == delta else { return nil }
        switch resolution.kind {
        case .tip:
            // Only a shortfall can be a tip; chips don't appear from nowhere.
            return delta < 0 ? resolution : nil
        case .assign:
            return players.contains { $0.id == resolution.playerID } ? resolution : nil
        case .split:
            return resolution
        }
    }

    /// Everyone is cashed out and the books close: either the bank balances
    /// exactly, or a resolution covers the difference.
    var isBalanced: Bool {
        allCashedOut && (bankDeltaMinor == 0 || activeResolution != nil)
    }

    /// The difference shared across `count` people in whole cents. The first
    /// few people take one extra (or one less) cent, so the shares always add
    /// up to exactly `amount` and nothing is rounded away.
    static func evenShares(of amount: Int, among count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let base = amount / count                     // truncates toward zero
        var shares = Array(repeating: base, count: count)
        let remainder = amount - base * count         // |remainder| < count
        let step = remainder > 0 ? 1 : -1
        for index in 0..<abs(remainder) { shares[index] += step }
        return shares
    }

    /// What the difference does to each player under the current resolution,
    /// in the same order as `players` (all zeros when it balances).
    func resolutionShares() -> [Int] {
        let delta = bankDeltaMinor
        guard delta != 0, let resolution = activeResolution else {
            return Array(repeating: 0, count: players.count)
        }
        switch resolution.kind {
        case .tip:
            return Array(repeating: 0, count: players.count)
        case .assign:
            return players.map { $0.id == resolution.playerID ? delta : 0 }
        case .split:
            return Self.evenShares(of: delta, among: players.count)
        }
    }

    /// Each player's net after the resolution, plus a "Tips" entry when the
    /// shortfall was recorded as tips. These always add up to exactly zero.
    /// Nil until the night is fully cashed out and balanced.
    func settlementEntries() -> [NetEntry]? {
        guard isBalanced else { return nil }
        let shares = resolutionShares()
        var entries: [NetEntry] = []
        for (index, player) in players.enumerated() {
            guard let cashOut = player.cashOutMinor else { return nil }
            entries.append(NetEntry(id: player.id, name: player.name, netMinor: cashOut - player.totalInMinor - shares[index]))
        }
        if let resolution = activeResolution, resolution.kind == .tip {
            entries.append(NetEntry(id: nil, name: "Tips", netMinor: -bankDeltaMinor))
        }
        return entries
    }

    func payments() -> [Payment]? {
        settlementEntries().map { Settlement.payments(for: $0).payments }
    }

    // MARK: Time

    /// Seconds actually played: start to end (or now), minus time on hold.
    func playtimeSeconds(at now: Date = Date()) -> Int {
        let end = endedAt ?? now
        let span = max(0, end.timeIntervalSince(startedAt))
        return max(0, Int((span - pausedInterval(until: end)).rounded(.down)))
    }

    /// Whole seconds spent on breaks so far — the part of the night that isn't played time.
    func pausedSeconds(at now: Date = Date()) -> Int {
        Int(pausedInterval(until: endedAt ?? now).rounded(.down))
    }

    private func pausedInterval(until end: Date) -> TimeInterval {
        var paused: TimeInterval = 0
        for pause in pauses {
            let from = max(pause.start, startedAt)
            let to = min(pause.end ?? end, end)
            if to > from { paused += to.timeIntervalSince(from) }
        }
        return paused
    }

    var timeZone: TimeZone { TimeZone(identifier: tzIdentifier) ?? .current }

    /// The calendar day the night started on, in the time zone it was played in.
    var localDay: DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.year, .month, .day], from: startedAt)
    }
}

// MARK: - Ordering

enum PlayerOrder {
    /// A stable, input-order-independent ordering: name (case-insensitive), then id.
    static func precedes(_ nameA: String, _ idA: UUID?, _ nameB: String, _ idB: UUID?) -> Bool {
        let comparison = nameA.localizedCaseInsensitiveCompare(nameB)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return (idA?.uuidString ?? "") < (idB?.uuidString ?? "")
    }
}

// MARK: - Changing a night

extension GameNight {
    func playerIndex(_ id: UUID) -> Int? { players.firstIndex { $0.id == id } }

    /// Adds a player who joins late, in for the default buy-in.
    @discardableResult
    mutating func addPlayer(name: String, at now: Date = Date()) -> PlayerLedger {
        let player = PlayerLedger(
            id: UUID(),
            name: PlayerNaming.clean(name, fallbackNumber: players.count + 1),
            buyIns: [BuyInEvent(id: UUID(), amountMinor: defaultBuyInMinor, at: now)],
            cashOutMinor: nil,
            cashedOutAt: nil
        )
        players.append(player)
        return player
    }

    /// Removes a player who hasn't cashed out. Returns false if they can't be removed.
    @discardableResult
    mutating func removePlayer(_ id: UUID) -> Bool {
        guard let index = playerIndex(id), !players[index].isCashedOut else { return false }
        players.remove(at: index)
        if myPlayerID == id { myPlayerID = nil }
        return true
    }

    /// The person holding this phone, if they were playing.
    var me: PlayerLedger? {
        myPlayerID.flatMap { id in players.first { $0.id == id } }
    }

    mutating func setMe(_ id: UUID?) {
        guard id == nil || playerIndex(id ?? UUID()) != nil else { return }
        myPlayerID = id
    }

    mutating func renamePlayer(_ id: UUID, to name: String) {
        guard let index = playerIndex(id) else { return }
        players[index].name = PlayerNaming.clean(name, fallbackNumber: index + 1)
    }

    /// Records a rebuy as its own event and returns it, so it can be undone.
    @discardableResult
    mutating func rebuy(_ playerID: UUID, amountMinor: Int? = nil, at now: Date = Date()) -> BuyInEvent? {
        guard let index = playerIndex(playerID), !players[index].isCashedOut else { return nil }
        let event = BuyInEvent(id: UUID(), amountMinor: amountMinor ?? defaultBuyInMinor, at: now)
        guard event.amountMinor > 0 else { return nil }
        players[index].buyIns.append(event)
        return event
    }

    /// Takes a buy-in event back out. A player always keeps at least their first.
    @discardableResult
    mutating func undoBuyIn(playerID: UUID, eventID: UUID) -> Bool {
        guard let index = playerIndex(playerID), players[index].buyIns.count > 1,
              let eventIndex = players[index].buyIns.firstIndex(where: { $0.id == eventID }) else { return false }
        players[index].buyIns.remove(at: eventIndex)
        return true
    }

    mutating func cashOut(_ playerID: UUID, amountMinor: Int, at now: Date = Date()) {
        guard let index = playerIndex(playerID), amountMinor >= 0 else { return }
        players[index].cashOutMinor = amountMinor
        players[index].cashedOutAt = now
    }

    mutating func clearCashOut(_ playerID: UUID) {
        guard let index = playerIndex(playerID) else { return }
        players[index].cashOutMinor = nil
        players[index].cashedOutAt = nil
    }

    /// Calls the game: the clock stops (any open pause ends with it).
    mutating func endPlay(at now: Date = Date()) {
        guard endedAt == nil else { return }
        if hasOpenPause { pauses[pauses.count - 1].end = now }
        endedAt = now
    }

    /// Takes "end night" back so play can carry on.
    mutating func resumePlay() {
        guard !isSettled else { return }
        endedAt = nil
        resolution = nil
    }

    mutating func pause(at now: Date = Date()) {
        guard isLive, !hasOpenPause else { return }
        pauses.append(PauseInterval(start: now, end: nil))
    }

    mutating func resumeFromPause(at now: Date = Date()) {
        guard hasOpenPause else { return }
        pauses[pauses.count - 1].end = now
    }

    /// Chooses how the bank's difference is settled. Ignored if it balances.
    mutating func resolveBank(_ kind: BankResolution.Kind, playerID: UUID? = nil) {
        let delta = bankDeltaMinor
        guard allCashedOut, delta != 0 else { resolution = nil; return }
        resolution = BankResolution(kind: kind, playerID: playerID, deltaMinor: delta)
    }

    /// Closes the night once everything adds up. Returns false if it doesn't.
    @discardableResult
    mutating func settle(at now: Date = Date()) -> Bool {
        guard isBalanced else { return false }
        if endedAt == nil { endPlay(at: now) }
        settledAt = now
        return true
    }

    /// Opens a settled night again to correct it.
    mutating func reopen() {
        settledAt = nil
    }

    /// Deleting keeps the content for now, so Undo can bring it back.
    mutating func markDeleted(at now: Date = Date()) {
        deletedAt = now
    }

    mutating func restore() {
        deletedAt = nil
    }

    /// What is left of a deleted night once Undo is over: when it started and
    /// that it was deleted — nothing about who played, where, or for how much.
    /// Other devices need the marker to stop showing the night; the server
    /// keeps exactly this and no more.
    var tombstone: GameNight {
        GameNight(
            schemaVersion: schemaVersion,
            id: id,
            startedAt: startedAt,
            tzIdentifier: tzIdentifier,
            currency: currency,
            defaultBuyInMinor: 0,
            colors: [],
            denominationsMinor: [:],
            players: [],
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}
