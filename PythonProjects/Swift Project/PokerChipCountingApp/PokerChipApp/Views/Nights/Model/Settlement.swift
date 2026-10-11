//
//  Settlement.swift
//  PokerChipApp
//
//  Turns everyone's net into the fewest, simplest payments: repeatedly match the
//  person owed the most with the person who owes the most. With n people that is
//  at most n − 1 payments, every cent is accounted for, and the result doesn't
//  depend on the order the players happen to be listed in.
//

import Foundation

struct Payment: Codable, Hashable, Identifiable {
    var fromID: UUID?
    var fromName: String
    var toID: UUID?
    var toName: String
    var amountMinor: Int

    /// A pair of people is matched at most once, so this is unique within a settlement.
    var id: String { "\(fromID?.uuidString ?? "house")>\(toID?.uuidString ?? "house")" }
}

enum Settlement {
    struct Outcome: Equatable {
        var payments: [Payment]
        /// Whatever didn't net to zero. Always 0 for a balanced night; non-zero
        /// only if the entries handed in didn't add up.
        var unbalancedMinor: Int
    }

    static func payments(for entries: [NetEntry]) -> Outcome {
        struct Party {
            var entry: NetEntry
            var remaining: Int
        }

        var creditors = entries.filter { $0.netMinor > 0 }.map { Party(entry: $0, remaining: $0.netMinor) }
        var debtors = entries.filter { $0.netMinor < 0 }.map { Party(entry: $0, remaining: -$0.netMinor) }
        let unbalanced = entries.reduce(0) { $0 + $1.netMinor }

        /// The party with the most outstanding; equal amounts go to whoever
        /// sorts first by name, then id, so the answer never depends on input order.
        func largest(_ parties: [Party]) -> Int? {
            parties.indices.max { a, b in
                if parties[a].remaining != parties[b].remaining { return parties[a].remaining < parties[b].remaining }
                return PlayerOrder.precedes(parties[b].entry.name, parties[b].entry.id, parties[a].entry.name, parties[a].entry.id)
            }
        }

        var payments: [Payment] = []
        while let creditorIndex = largest(creditors), let debtorIndex = largest(debtors) {
            let amount = min(creditors[creditorIndex].remaining, debtors[debtorIndex].remaining)
            payments.append(
                Payment(
                    fromID: debtors[debtorIndex].entry.id,
                    fromName: debtors[debtorIndex].entry.name,
                    toID: creditors[creditorIndex].entry.id,
                    toName: creditors[creditorIndex].entry.name,
                    amountMinor: amount
                )
            )
            creditors[creditorIndex].remaining -= amount
            debtors[debtorIndex].remaining -= amount
            if creditors[creditorIndex].remaining == 0 { creditors.remove(at: creditorIndex) }
            if debtors[debtorIndex].remaining == 0 { debtors.remove(at: debtorIndex) }
        }
        return Outcome(payments: payments, unbalancedMinor: unbalanced)
    }

    /// "Sam → Alex $23.50", one per line, ready to paste into the group chat.
    static func text(for payments: [Payment], currency: String = Money.defaultCurrencyCode, locale: Locale = .current) -> String {
        payments
            .map { "\($0.fromName) → \($0.toName) \(Money.format(cents: $0.amountMinor, currencyCode: currency, locale: locale))" }
            .joined(separator: "\n")
    }
}
