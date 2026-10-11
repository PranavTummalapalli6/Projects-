//
//  Money.swift
//  PokerChipApp
//
//  Formatting and parsing for money and durations. Everything that shows or
//  reads an amount goes through here, so currency symbols follow the device
//  locale instead of a hard-coded "$", and a comma-decimal keyboard ("25,50")
//  parses correctly instead of silently failing.
//

import Foundation

enum Money {
    /// The currency used for new sessions. v1.0 is USD-only; formatting is
    /// already currency-aware so adding more is a data change, not a rewrite.
    static let defaultCurrencyCode = "USD"

    private static let formatterCache = NSCache<NSString, NumberFormatter>()

    private static func currencyFormatter(code: String, locale: Locale, fractionDigits: Int = 2) -> NumberFormatter {
        let key = "\(code)|\(locale.identifier)|\(fractionDigits)" as NSString
        if let cached = formatterCache.object(forKey: key) { return cached }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = locale
        // Chip math is exact to the cent, so always show both digits.
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatterCache.setObject(formatter, forKey: key)
        return formatter
    }

    static func format(_ amount: Double, currencyCode: String = defaultCurrencyCode, locale: Locale = .current) -> String {
        currencyFormatter(code: currencyCode, locale: locale).string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    /// "$10" for a whole amount, "$12.50" otherwise — for tight spots such as
    /// quick-pick buttons.
    static func compact(_ amount: Double, currencyCode: String = defaultCurrencyCode, locale: Locale = .current) -> String {
        guard amount == amount.rounded() else { return format(amount, currencyCode: currencyCode, locale: locale) }
        return currencyFormatter(code: currencyCode, locale: locale, fractionDigits: 0)
            .string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    /// "2.50 US dollars" — an amount as words, for VoiceOver.
    static func spoken(cents: Int, currencyCode: String = defaultCurrencyCode, locale: Locale = .current) -> String {
        let key = "spoken|\(currencyCode)|\(locale.identifier)" as NSString
        let formatter: NumberFormatter
        if let cached = formatterCache.object(forKey: key) {
            formatter = cached
        } else {
            formatter = NumberFormatter()
            formatter.numberStyle = .currencyPlural
            formatter.currencyCode = currencyCode
            formatter.locale = locale
            formatterCache.setObject(formatter, forKey: key)
        }
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? format(cents: cents, currencyCode: currencyCode, locale: locale)
    }

    /// The symbol to show beside an amount field ("$").
    static func currencySymbol(currencyCode: String = defaultCurrencyCode, locale: Locale = .current) -> String {
        currencyFormatter(code: currencyCode, locale: locale).currencySymbol ?? currencyCode
    }

    static func format(cents: Int, currencyCode: String = defaultCurrencyCode, locale: Locale = .current) -> String {
        format(Double(cents) / 100, currencyCode: currencyCode, locale: locale)
    }

    /// "+$13.00" / "−$7.50" / "$0.00" — the sign is always explicit for a
    /// result, and a true minus sign is used so it reads clearly at a glance.
    static func formatSigned(cents: Int, currencyCode: String = defaultCurrencyCode, locale: Locale = .current) -> String {
        let magnitude = format(cents: abs(cents), currencyCode: currencyCode, locale: locale)
        if cents > 0 { return "+\(magnitude)" }
        if cents < 0 { return "\u{2212}\(magnitude)" }
        return magnitude
    }

    /// An amount for a text field: no currency symbol, no trailing ".00" for
    /// whole numbers ("25", "25.5"), using the locale's decimal separator.
    static func plain(_ amount: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    /// Parses what a person typed using the device locale. Strict on purpose:
    /// "25,5" in a US locale is rejected rather than quietly read as 255.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = false
        formatter.isLenient = false
        return formatter.number(from: trimmed)?.doubleValue
    }

    /// Whole cents for a dollar amount, without float drift (0.1 + 0.2 style).
    static func cents(_ amount: Double) -> Int {
        Int((amount * 100).rounded())
    }
}

enum DurationFormat {
    /// "04:32" under an hour, "1:12:44" from an hour on — the clock face.
    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// "0m", "45m", "3h 20m" — for summaries.
    static func compact(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes)m" }
        return "\(hours)h \(minutes)m"
    }

    /// "1 hour, 12 minutes" — for VoiceOver.
    static func spoken(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(max(0, seconds))) ?? "\(seconds) seconds"
    }
}
