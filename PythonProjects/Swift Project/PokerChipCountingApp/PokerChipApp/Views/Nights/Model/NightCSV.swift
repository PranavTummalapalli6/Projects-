//
//  NightCSV.swift
//  PokerChipApp
//
//  The person's own record of their nights as a spreadsheet: one row per player
//  per night, money as plain decimals ("-12.50", whatever the phone's language),
//  and quoting that survives names and notes with commas, quotes and line
//  breaks. What is written can be read back exactly.
//

import Foundation

/// RFC 4180: fields with a comma, a quote or a line break are quoted, quotes
/// are doubled, and rows end in CRLF.
enum CSV {
    static func encode(_ rows: [[String]]) -> String {
        rows.map { row in
            // A row of one empty field would be a blank line, which reads as no row at all.
            if row == [""] { return "\"\"" }
            return row.map(quoted).joined(separator: ",")
        }
        .map { $0 + "\r\n" }
        .joined()
    }

    private static func quoted(_ field: String) -> String {
        let needsQuotes = field.unicodeScalars.contains { [",", "\"", "\r", "\n"].contains($0) }
            || field.hasPrefix(" ") || field.hasSuffix(" ")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// The rows in `text`, or nil if it isn't well-formed CSV (an unterminated
    /// quote, or a quote in the middle of an unquoted field).
    static func parse(_ text: String) -> [[String]]? {
        enum State { case fieldStart, unquoted, quoted, quoteInQuoted }

        let comma: Unicode.Scalar = ",", quote: Unicode.Scalar = "\"", cr: Unicode.Scalar = "\r", lf: Unicode.Scalar = "\n"
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var state = State.fieldStart

        func endField() { row.append(String(field)); field = String.UnicodeScalarView() }
        func endRow() { endField(); rows.append(row); row = [] }

        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            switch state {
            case .fieldStart:
                if scalar == quote { state = .quoted }
                else if scalar == comma { endField() }
                else if scalar == cr || scalar == lf {
                    endRow()
                    if scalar == cr, index + 1 < scalars.count, scalars[index + 1] == lf { index += 1 }
                } else { field.append(scalar); state = .unquoted }
            case .unquoted:
                if scalar == quote { return nil }
                else if scalar == comma { endField(); state = .fieldStart }
                else if scalar == cr || scalar == lf {
                    endRow(); state = .fieldStart
                    if scalar == cr, index + 1 < scalars.count, scalars[index + 1] == lf { index += 1 }
                } else { field.append(scalar) }
            case .quoted:
                if scalar == quote { state = .quoteInQuoted } else { field.append(scalar) }
            case .quoteInQuoted:
                if scalar == quote { field.append(quote); state = .quoted }
                else if scalar == comma { endField(); state = .fieldStart }
                else if scalar == cr || scalar == lf {
                    endRow(); state = .fieldStart
                    if scalar == cr, index + 1 < scalars.count, scalars[index + 1] == lf { index += 1 }
                } else { return nil }
            }
            index += 1
        }

        switch state {
        case .quoted: return nil
        case .fieldStart: if !row.isEmpty { endRow() }
        case .unquoted, .quoteInQuoted: endRow()
        }
        return rows
    }
}

enum NightCSV {
    static let columns = [
        "night_id", "started_utc", "local_date", "timezone", "place", "currency", "stake",
        "player", "is_me", "total_in", "cash_out", "result", "playtime_minutes", "notes",
    ]

    struct Row: Equatable {
        var nightID: String
        var startedUTC: String
        var localDate: String
        var timeZone: String
        var place: String
        var currency: String
        var stake: String
        var player: String
        var isMe: Bool
        var totalIn: String
        /// Blank until the player has cashed out.
        var cashOut: String
        /// After the bank was reconciled; blank until the night balances.
        var result: String
        var playtimeMinutes: Int
        var notes: String

        var fields: [String] {
            [nightID, startedUTC, localDate, timeZone, place, currency, stake, player, isMe ? "yes" : "no",
             totalIn, cashOut, result, String(playtimeMinutes), notes]
        }

        init(
            nightID: String, startedUTC: String, localDate: String, timeZone: String, place: String, currency: String,
            stake: String, player: String, isMe: Bool, totalIn: String, cashOut: String, result: String,
            playtimeMinutes: Int, notes: String
        ) {
            self.nightID = nightID; self.startedUTC = startedUTC; self.localDate = localDate; self.timeZone = timeZone
            self.place = place; self.currency = currency; self.stake = stake; self.player = player; self.isMe = isMe
            self.totalIn = totalIn; self.cashOut = cashOut; self.result = result
            self.playtimeMinutes = playtimeMinutes; self.notes = notes
        }

        init?(fields: [String]) {
            guard fields.count == NightCSV.columns.count, let minutes = Int(fields[12]), ["yes", "no"].contains(fields[8]) else { return nil }
            self.init(
                nightID: fields[0], startedUTC: fields[1], localDate: fields[2], timeZone: fields[3], place: fields[4],
                currency: fields[5], stake: fields[6], player: fields[7], isMe: fields[8] == "yes", totalIn: fields[9],
                cashOut: fields[10], result: fields[11], playtimeMinutes: minutes, notes: fields[13]
            )
        }
    }

    /// "-12.50": whole units and cents, always a point and two digits, in any locale.
    static func amount(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let magnitude = abs(cents)
        return "\(sign)\(magnitude / 100).\(String(format: "%02d", magnitude % 100))"
    }

    /// One row per player per night, oldest night first, players in seat order. A
    /// night that was shortened by tips also gets a "(house)" row, so the results
    /// of every closed night add up to zero.
    static func rows(for nights: [GameNight], now: Date = Date()) -> [Row] {
        let ordered = nights.filter { !$0.isDeleted }
            .sorted { $0.startedAt != $1.startedAt ? $0.startedAt < $1.startedAt : $0.id.uuidString < $1.id.uuidString }
        var rows: [Row] = []
        for night in ordered {
            let entries = night.settlementEntries() ?? []
            let minutes = night.playtimeSeconds(at: now) / 60
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = night.timeZone
            let day = calendar.dateComponents([.year, .month, .day], from: night.startedAt)
            let localDate = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)

            func row(player: String, isMe: Bool, totalIn: String, cashOut: String, result: String) -> Row {
                Row(
                    nightID: night.id.uuidString, startedUTC: NightCoding.string(from: night.startedAt), localDate: localDate,
                    timeZone: night.tzIdentifier, place: night.location ?? "", currency: night.currency,
                    stake: amount(night.defaultBuyInMinor), player: player, isMe: isMe, totalIn: totalIn,
                    cashOut: cashOut, result: result, playtimeMinutes: minutes, notes: night.notes ?? ""
                )
            }

            for player in night.players {
                let result = entries.first { $0.id == player.id }.map { amount($0.netMinor) } ?? ""
                rows.append(row(
                    player: player.name, isMe: night.myPlayerID == player.id, totalIn: amount(player.totalInMinor),
                    cashOut: player.cashOutMinor.map(amount) ?? "", result: result
                ))
            }
            if let house = entries.first(where: { $0.id == nil }) {
                rows.append(row(player: "(house)", isMe: false, totalIn: "", cashOut: "", result: amount(house.netMinor)))
            }
        }
        return rows
    }

    static func text(for nights: [GameNight], now: Date = Date()) -> String {
        CSV.encode([columns] + rows(for: nights, now: now).map(\.fields))
    }

    /// Reads back what `text(for:)` wrote; nil if it isn't this file.
    static func parse(_ text: String) -> [Row]? {
        guard let table = CSV.parse(text), table.first == columns else { return nil }
        var rows: [Row] = []
        for fields in table.dropFirst() {
            guard let row = Row(fields: fields) else { return nil }
            rows.append(row)
        }
        return rows
    }

    /// Where the export is written, named for the day.
    static func fileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "chip-counter-nights-\(formatter.string(from: now)).csv"
    }
}
