//
//  NightCoding.swift
//  PokerChipApp
//
//  One JSON shape for a night, used for the files on the device and for the
//  backend alike. Dates are ISO-8601 with fractional seconds (so two edits in
//  the same second still order correctly) and keys are sorted, so the same
//  night always produces the same bytes.
//

import Foundation

enum NightCoding {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        withFraction.string(from: date)
    }

    /// Accepts the timestamp with or without fractional seconds.
    static func date(from string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }

    /// The stored form keeps whole milliseconds, so a date compared before and
    /// after a save and reload is the same date.
    static func quantized(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1_000).rounded(.down) / 1_000)
    }

    /// The night exactly as saving and reloading it would give it back: every
    /// date at whole milliseconds. Keeping nights in this form means what is in
    /// memory, on disk and on the wire are always equal, so "has this changed?"
    /// never turns on a fraction of a millisecond.
    static func canonical(_ night: GameNight) -> GameNight {
        guard let data = try? makeEncoder().encode(night),
              let restored = try? makeDecoder().decode(GameNight.self, from: data)
        else { return night }
        return restored
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO-8601 date: \(text)")
            }
            return date
        }
        return decoder
    }
}
