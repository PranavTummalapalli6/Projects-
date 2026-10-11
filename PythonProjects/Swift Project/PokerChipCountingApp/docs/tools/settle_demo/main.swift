//
//  main.swift: settle_demo
//
//  Runs the app's real bank-check and settle-up code (GameNight, NightMath, Settlement) on the cases
//  quoted in docs/HOW_IT_WORKS.md section 9, so those numbers can be reproduced. The four app source files
//  are compiled as they are. From the repository root:
//
//    swiftc -O -o /tmp/settle_demo docs/tools/settle_demo/main.swift \
//        PokerChipApp/Views/Nights/Model/Settlement.swift PokerChipApp/Views/Nights/Model/NightMath.swift \
//        PokerChipApp/Views/Nights/Model/GameNight.swift PokerChipApp/Views/Core/Money.swift
//    /tmp/settle_demo
//

import Foundation

func entry(_ name: String, _ minor: Int) -> NetEntry { NetEntry(id: UUID(), name: name, netMinor: minor) }

func show(_ title: String, _ nets: [(String, Int)]) {
    let outcome = Settlement.payments(for: nets.map { entry($0.0, $0.1) })
    print("## \(title)")
    print("   nets: " + nets.map { "\($0.0) \($0.1 >= 0 ? "+" : "")\($0.1)" }.joined(separator: ", "))
    for p in outcome.payments { print("   \(p.fromName) pays \(p.toName) \(p.amountMinor)") }
    print("   \(outcome.payments.count) payments for \(nets.count) people; unbalanced \(outcome.unbalancedMinor)")
}

show("greedy matching, four people", [("A", 5000), ("B", 3000), ("C", -2000), ("D", -6000)])
show("greedy is not always the fewest: two zero-sum groups hidden in five people", [("A", 500), ("B", 400), ("C", 300), ("D", -500), ("E", -700)])
print()

print("## evenShares (the first people take the extra cent)")
for (amount, count) in [(-100, 3), (100, 3), (7, 4), (-7, 4), (10, 5), (0, 3)] {
    print("   evenShares(\(amount), among: \(count)) = \(GameNight.evenShares(of: amount, among: count))")
}
print()

func night(cashOuts: [Int], buyIn: Int = 2000) -> GameNight {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var n = GameNight.start(now: start, timeZone: TimeZone(identifier: "UTC")!, buyInMinor: buyIn,
                            playerNames: ["Alex", "Blair", "Casey"], colors: ["White", "Red"],
                            denominationsMinor: ["White": 25, "Red": 100])
    n.endPlay(at: start.addingTimeInterval(3 * 3600))
    for (index, amount) in cashOuts.enumerated() { n.cashOut(n.players[index].id, amountMinor: amount, at: start) }
    return n
}

func report(_ title: String, _ n: GameNight) {
    print("## \(title)")
    print("   in \(n.totalInMinor), out \(n.totalOutMinor), bank difference \(n.bankDeltaMinor), balanced: \(n.isBalanced)")
    if let entries = n.settlementEntries() {
        print("   nets after the resolution: " + entries.map { "\($0.name) \($0.netMinor)" }.joined(separator: ", ") + "  (sum \(entries.reduce(0) { $0 + $1.netMinor }))")
        for p in n.payments() ?? [] { print("   \(p.fromName) pays \(p.toName) \(p.amountMinor)") }
    } else {
        print("   not settled yet: the bank must balance or a resolution must cover the difference")
    }
}

var n = night(cashOuts: [2500, 2000, 1400])         // $60 in, $59 out: $1.00 short
report("a $1.00 shortfall, unresolved", n)
n.resolveBank(.tip);                      report("... recorded as a tip", n)
n.resolveBank(.assign, playerID: n.players[2].id); report("... put on Casey", n)
n.resolveBank(.split);                    report("... split three ways", n)
n.cashOut(n.players[2].id, amountMinor: 1500, at: Date(timeIntervalSince1970: 1_800_000_100))
report("... after Casey's cash-out is corrected to $15.00 (the old choice no longer applies)", n)

var over = night(cashOuts: [2500, 2000, 1600])      // $61 out of $60: $1.00 over
over.resolveBank(.tip)
report("a $1.00 overage with a tip chosen (a tip can only cover a shortfall)", over)
over.resolveBank(.split)
report("... split three ways", over)
