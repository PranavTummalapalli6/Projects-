//
//  ActivityMoney.swift
//  PokerChipApp
//
//  Compiled into the app and its widgets. Whole minor units (cents) as a price in
//  the night's currency, for places that can't reach the app's own `Money`.
//

import Foundation

enum ActivityMoney {
    static func format(minor: Int, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        let value = Double(minor) / pow(10, Double(formatter.maximumFractionDigits))
        return formatter.string(from: NSNumber(value: value)) ?? "\(minor)"
    }

    /// 3723 → "1:02:03"; under an hour, "2:03".
    static func clock(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3_600, minutes = (total % 3_600) / 60, secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}
