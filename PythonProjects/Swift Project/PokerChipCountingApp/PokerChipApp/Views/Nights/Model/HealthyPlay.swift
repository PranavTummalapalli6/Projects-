//
//  HealthyPlay.swift
//  PokerChipApp
//
//  The tools that help someone keep poker fun: limits they set for themselves,
//  a gentle word when a week goes past them, a break they can commit to, a
//  reminder during a long night, and where to turn if it has stopped being fun.
//
//  The tone is the point. Nothing here blocks anyone from their own history or
//  from finishing a night, nothing counts money or time against them in red, and
//  every message is something a good friend might say.
//

import Foundation

/// Limits the person has chosen, from Settings.
struct PlayLimits: Equatable {
    /// Hours of play in a week at which they'd like a word. Also the Poker Health limit.
    var weeklyHours: Double
    /// A loss, in whole currency units, over the last seven days that deserves a word; nil when off.
    var weeklyLoss: Double?
    /// Hours into a night at which to suggest a break; nil when off.
    var reminderHours: Double?
    /// A break they committed to: no new nights until then.
    var coolOffUntil: Date?

    init(weeklyHours: Double = AppPreferences.defaultWeeklyHoursCap, weeklyLoss: Double? = nil, reminderHours: Double? = nil, coolOffUntil: Date? = nil) {
        self.weeklyHours = weeklyHours
        self.weeklyLoss = weeklyLoss
        self.reminderHours = reminderHours
        self.coolOffUntil = coolOffUntil
    }

    /// Reads the limits from UserDefaults (the same keys `@AppStorage` in Settings writes).
    static func stored(defaults: UserDefaults = .standard) -> PlayLimits {
        let loss = defaults.double(forKey: PrefKey.weeklyLossLimit)
        let reminder = defaults.double(forKey: PrefKey.sessionReminderHours)
        let coolOff = defaults.double(forKey: PrefKey.coolOffUntil)
        let hours = defaults.double(forKey: PrefKey.weeklyHoursCap)
        return PlayLimits(
            weeklyHours: hours > 0 ? hours : AppPreferences.defaultWeeklyHoursCap,
            weeklyLoss: loss > 0 ? loss : nil,
            reminderHours: reminder > 0 ? reminder : nil,
            coolOffUntil: coolOff > 0 ? Date(timeIntervalSince1970: coolOff) : nil
        )
    }
}

enum HealthyPlay {
    // MARK: The week so far

    /// A gentle word about the week, if one is due.
    struct Nudge: Equatable {
        enum Reason: String { case time, loss }

        let reason: Reason
        /// 1 = "you're close", 2 = "you're past it". Dismissing a word keeps the same
        /// or a milder one away for the rest of the week — not a stronger one.
        let level: Int
        let week: String
        let message: String

        /// What is remembered when the person says "Got it".
        var id: String { "\(week)|\(reason.rawValue)|\(level)" }

        func isHidden(byDismissed dismissed: String) -> Bool {
            let parts = dismissed.split(separator: "|").map(String.init)
            guard parts.count == 3, parts[0] == week, parts[1] == reason.rawValue, let seen = Int(parts[2]) else { return false }
            return level <= seen
        }
    }

    /// Whether this week has gone past a limit the person set — or is close to
    /// the time limit. Nothing is said without a limit set, and only closed
    /// nights count towards the loss.
    static func nudge(
        nights: [GameNight],
        limits: PlayLimits,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        currency: String = Money.defaultCurrencyCode
    ) -> Nudge? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let weekID = "\(week.yearForWeekOfYear ?? 0)-W\(week.weekOfYear ?? 0)"

        let seconds = WeeklySummary.make(from: nights, now: now, timeZone: timeZone).totalSeconds
        let limitSeconds = limits.weeklyHours * 3_600

        if let loss = limits.weeklyLoss, loss > 0, weeklyNetMinor(nights: nights, now: now, timeZone: timeZone) <= -Money.cents(loss) {
            let down = Money.format(cents: -weeklyNetMinor(nights: nights, now: now, timeZone: timeZone), currencyCode: currency)
            return Nudge(
                reason: .loss,
                level: 2,
                week: weekID,
                message: "You're down \(down) over the last seven days — past the \(Money.format(loss, currencyCode: currency)) you set. A few days away from the table could be a good idea."
            )
        }
        if limitSeconds > 0, Double(seconds) >= limitSeconds {
            return Nudge(
                reason: .time,
                level: 2,
                week: weekID,
                message: "That's \(DurationFormat.compact(seconds)) at the table this week — past the \(Int(limits.weeklyHours))-hour limit you set. A night off might feel good."
            )
        }
        if limitSeconds > 0, Double(seconds) >= limitSeconds * 0.8 {
            return Nudge(
                reason: .time,
                level: 1,
                week: weekID,
                message: "You're close to the \(Int(limits.weeklyHours))-hour limit you set for the week (\(DurationFormat.compact(seconds)) so far)."
            )
        }
        return nil
    }

    /// The person's own net over the last seven local days, over closed nights.
    static func weeklyNetMinor(nights: [GameNight], now: Date = Date(), timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let from = calendar.date(byAdding: .day, value: -(WeeklySummary.windowDays - 1), to: calendar.startOfDay(for: now)) else { return 0 }
        return nights
            .filter { $0.isSettled && !$0.isDeleted && $0.startedAt >= from && $0.startedAt <= now }
            .compactMap { NightSummary(night: $0, now: now).myNetMinor }
            .reduce(0, +)
    }

    // MARK: Taking a break

    enum Break: CaseIterable, Identifiable {
        case day, threeDays, week

        var id: Self { self }

        var title: String {
            switch self {
            case .day: return "24 hours"
            case .threeDays: return "3 days"
            case .week: return "7 days"
            }
        }

        var seconds: TimeInterval {
            switch self {
            case .day: return 86_400
            case .threeDays: return 3 * 86_400
            case .week: return 7 * 86_400
            }
        }
    }

    static func isCoolingOff(_ limits: PlayLimits, now: Date = Date()) -> Bool {
        guard let until = limits.coolOffUntil else { return false }
        return until > now
    }

    /// When a break started now would end.
    static func coolOffEnd(for length: Break, from now: Date = Date()) -> Date {
        now.addingTimeInterval(length.seconds)
    }

    // MARK: A reminder during a long night

    enum ReminderPlan: Equatable {
        case cancel
        /// Fire this many seconds from now.
        case schedule(after: TimeInterval)
    }

    /// When to remind someone to take a break: `hours` of actual play into the
    /// night (time on a break doesn't count). Nothing is scheduled for a night
    /// that is over, paused, or already past the mark — no nagging after the fact.
    static func reminderPlan(for night: GameNight?, hours: Double?, now: Date = Date()) -> ReminderPlan {
        guard let hours, hours > 0, let night, night.isLive, !night.hasOpenPause else { return .cancel }
        let remaining = hours * 3_600 - TimeInterval(night.playtimeSeconds(at: now))
        return remaining > 0 ? .schedule(after: max(remaining, 5)) : .cancel
    }

    static func reminderBody(hours: Double) -> String {
        let text = hours == hours.rounded() ? "\(Int(hours)) hour\(hours == 1 ? "" : "s")" : "\(hours) hours"
        return "You've been playing for about \(text). Everything is saved — step away for a few minutes if you like."
    }
}

// MARK: - Where to turn

struct Helpline: Equatable, Identifiable {
    let id: String
    let name: String
    /// How the number is written for reading, e.g. "1-800-MY-RESET (1-800-697-3738)".
    let phoneDisplay: String?
    /// Digits only, for the call link.
    let phoneDigits: String?
    /// Digits to text, when the service takes texts.
    let textDigits: String?
    let website: String
    let detail: String

    var callURL: URL? { phoneDigits.flatMap { URL(string: "tel:\($0)") } }
    var textURL: URL? { textDigits.flatMap { URL(string: "sms:\($0)") } }
    var websiteURL: URL? { URL(string: website) }
}

enum HelplineDirectory {
    /// When each entry was last checked against the organisation's own site.
    static let verifiedOn = "9 October 2026"

    static func helplines(for region: String?) -> [Helpline] {
        switch region?.uppercased() {
        case "US", "PR", "GU", "VI":
            return [usNational]
        case "GB", "UK":
            return [gamCare]
        case "AU":
            return [australia]
        case "CA":
            return [canada, finder]
        default:
            return [finder]
        }
    }

    /// The US national line changed on 29 January 2026: the National Council on
    /// Problem Gambling adopted 1-800-MY-RESET, and the old 1-800-GAMBLER number
    /// went back to a New Jersey state council. 1-800-522-4700 still works.
    static let usNational = Helpline(
        id: "us",
        name: "National Problem Gambling Helpline",
        phoneDisplay: "1-800-MY-RESET (1-800-697-3738)",
        phoneDigits: "18006973738",
        textDigits: "18006973738",
        website: "https://1800myreset.org",
        detail: "Call, text or chat, any time. Free and confidential."
    )

    static let gamCare = Helpline(
        id: "gb",
        name: "National Gambling Helpline (GamCare)",
        phoneDisplay: "0808 8020 133",
        phoneDigits: "08088020133",
        textDigits: nil,
        website: "https://www.gamcare.org.uk",
        detail: "Free, any time of day or night. Chat is on their website."
    )

    static let australia = Helpline(
        id: "au",
        name: "Gambling Help",
        phoneDisplay: "1800 858 858",
        phoneDigits: "1800858858",
        textDigits: nil,
        website: "https://www.gamblinghelponline.org.au",
        detail: "Free and confidential, any time. Online chat is on their website."
    )

    static let canada = Helpline(
        id: "ca",
        name: "Gambling helplines by province",
        phoneDisplay: nil,
        phoneDigits: nil,
        textDigits: nil,
        website: "https://gamblingguidelines.ca/getting-help/",
        detail: "Canada has no single national line; this lists the free one for each province and territory."
    )

    static let finder = Helpline(
        id: "world",
        name: "Find a helpline near you",
        phoneDisplay: nil,
        phoneDigits: nil,
        textDigits: nil,
        website: "https://findahelpline.com/topics/gambling",
        detail: "A directory of free, confidential gambling helplines in countries around the world."
    )
}
