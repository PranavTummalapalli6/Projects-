//
//  MoneyTests.swift
//  PokerChipAppTests
//
//  Amounts and durations are formatted and parsed in one place. These pin the
//  behaviour that used to be wrong: a hard-coded "$", and `Double(text)`
//  failing for a comma-decimal keyboard.
//

import XCTest
@testable import PokerChipApp

final class MoneyTests: XCTestCase {
    private let us = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    // MARK: Formatting

    func testFormatsDollarsWithBothFractionDigits() {
        XCTAssertEqual(Money.format(25, locale: us), "$25.00")
        XCTAssertEqual(Money.format(0.05, locale: us), "$0.05")
        XCTAssertEqual(Money.format(1234.5, locale: us), "$1,234.50")
    }

    func testFormatsWholeCents() {
        XCTAssertEqual(Money.format(cents: 1250, locale: us), "$12.50")
        XCTAssertEqual(Money.format(cents: 5, locale: us), "$0.05")
        XCTAssertEqual(Money.format(cents: 0, locale: us), "$0.00")
    }

    func testSeparatorsFollowTheDeviceLocale() {
        let formatted = Money.format(1234.5, locale: german)
        XCTAssertTrue(formatted.contains("1.234,50"), "got \(formatted)")
        XCTAssertFalse(formatted.hasPrefix("$"), "the symbol moves to the end in German: \(formatted)")
    }

    func testSignedAmountsAlwaysShowTheirSignWithATrueMinus() {
        XCTAssertEqual(Money.formatSigned(cents: 1300, locale: us), "+$13.00")
        XCTAssertEqual(Money.formatSigned(cents: -750, locale: us), "\u{2212}$7.50")
        XCTAssertEqual(Money.formatSigned(cents: 0, locale: us), "$0.00")
    }

    func testCompactDropsTheCentsOnlyForWholeAmounts() {
        XCTAssertEqual(Money.compact(10, locale: us), "$10")
        XCTAssertEqual(Money.compact(100, locale: us), "$100")
        XCTAssertEqual(Money.compact(12.5, locale: us), "$12.50")
    }

    func testPlainAmountsForTextFieldsHaveNoSymbolOrTrailingZeros() {
        XCTAssertEqual(Money.plain(25, locale: us), "25")
        XCTAssertEqual(Money.plain(25.5, locale: us), "25.5")
        XCTAssertEqual(Money.plain(25.5, locale: german), "25,5")
    }

    func testTheCurrencySymbolIsTheDollarSign() {
        XCTAssertEqual(Money.currencySymbol(locale: us), "$")
    }

    // MARK: Parsing

    func testParsesWhatSomeoneTypedInTheirOwnLocale() {
        XCTAssertEqual(Money.parse("25", locale: us), 25)
        XCTAssertEqual(Money.parse("25.50", locale: us), 25.5)
        XCTAssertEqual(Money.parse("  12.5 ", locale: us), 12.5)
        XCTAssertEqual(Money.parse("25,5", locale: german), 25.5)
    }

    func testRejectsInputThatIsNotAnAmount() {
        XCTAssertNil(Money.parse("", locale: us))
        XCTAssertNil(Money.parse("   ", locale: us))
        XCTAssertNil(Money.parse("abc", locale: us))
        XCTAssertNil(Money.parse("12.5.1", locale: us))
    }

    func testAComma_DecimalIsRejectedInADotDecimalLocaleInsteadOfBeingReadAsAThousand() {
        // "25,5" must not quietly become 255.
        XCTAssertNotEqual(Money.parse("25,5", locale: us), 255)
        XCTAssertNil(Money.parse("25,5", locale: us))
    }

    // MARK: Cents

    func testCentsAreExactDespiteFloatingPointDrift() {
        XCTAssertEqual(Money.cents(0.1 + 0.2), 30)
        XCTAssertEqual(Money.cents(19.99), 1999)
        XCTAssertEqual(Money.cents(0.29), 29)
        XCTAssertEqual(Money.cents(25), 2500)
    }

    func testCentsRoundTripThroughDollars() {
        for cents in [0, 5, 10, 25, 99, 100, 1999, 250_000] {
            XCTAssertEqual(Money.cents(Double(cents) / 100), cents)
        }
    }
}

final class DurationFormatTests: XCTestCase {
    func testClockShowsMinutesAndSecondsUnderAnHour() {
        XCTAssertEqual(DurationFormat.clock(0), "00:00")
        XCTAssertEqual(DurationFormat.clock(59), "00:59")
        XCTAssertEqual(DurationFormat.clock(61), "01:01")
        XCTAssertEqual(DurationFormat.clock(3_599), "59:59")
    }

    func testClockAddsHoursFromAnHourOn() {
        XCTAssertEqual(DurationFormat.clock(3_600), "1:00:00")
        XCTAssertEqual(DurationFormat.clock(4_364), "1:12:44")
        XCTAssertEqual(DurationFormat.clock(36_000 + 59), "10:00:59")
    }

    func testANegativeDurationNeverShowsAMinusSign() {
        XCTAssertEqual(DurationFormat.clock(-30), "00:00")
        XCTAssertEqual(DurationFormat.compact(-30), "0m")
    }

    func testCompactSummaries() {
        XCTAssertEqual(DurationFormat.compact(0), "0m")
        XCTAssertEqual(DurationFormat.compact(59), "0m")
        XCTAssertEqual(DurationFormat.compact(2_700), "45m")
        XCTAssertEqual(DurationFormat.compact(12_000), "3h 20m")
    }

    func testSpokenDurationsAreWords() {
        let spoken = DurationFormat.spoken(4_364)
        XCTAssertTrue(spoken.contains("1 hour"), spoken)
        XCTAssertTrue(spoken.contains("12 minutes"), spoken)
        XCTAssertFalse(spoken.contains(":"), spoken)
    }
}
