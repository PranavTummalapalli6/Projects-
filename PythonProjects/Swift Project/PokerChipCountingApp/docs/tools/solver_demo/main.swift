//
//  main.swift: solver_demo
//
//  Runs the app's real chip solver (calculateFlexibleChipDistribution), planner (ChipPlanner) and
//  blinds planner (BlindsPlanner) on the inputs quoted in docs/HOW_IT_WORKS.md and prints what they
//  return, so those numbers can be reproduced rather than taken on trust. The app's two source files
//  are compiled as they are; nothing here changes them. From the repository root:
//
//    swiftc -O -o /tmp/solver_demo \
//        docs/tools/solver_demo/Support.swift docs/tools/solver_demo/main.swift \
//        PokerChipApp/Views/Denominations/DenominationEngine.swift \
//        PokerChipApp/Views/Denominations/BlindsPlanner.swift
//    /tmp/solver_demo
//

import Foundation

func dollars(_ cents: Int) -> String {
    cents % 100 == 0 ? "$\(cents / 100)" : String(format: "$%.2f", Double(cents) / 100)
}

func show(_ label: String, buyIn: Double, players: Int, colors: [String]) {
    let (counts, values) = calculateFlexibleChipDistribution(buyIn: buyIn, players: players, availableColors: Set(colors))
    print("## \(label): buy-in \(dollars(Int((buyIn * 100).rounded()))), \(players) players, \(colors.joined(separator: "/"))")
    guard let counts else { print("   -> no stack (too small)"); return }
    var total = 0, chips = 0
    for c in allChipColors where counts[c] != nil {
        let v = Int((values[c]! * 100).rounded())
        total += v * counts[c]!; chips += counts[c]!
        print("   \(c.padding(toLength: 6, withPad: " ", startingAt: 0)) \(String(counts[c]!).padding(toLength: 3, withPad: " ", startingAt: 0)) x \(dollars(v))")
    }
    print("   chips \(chips), worth \(dollars(total))")
}

func showPlan(_ label: String, buyIn: Double, players: Int, colors: [String], inventory: ChipInventory? = nil, locked: [String: Int] = [:]) {
    let plan = ChipPlanner.plan(buyIn: buyIn, players: players, colors: Set(colors), inventory: inventory, lockedValues: locked)
    print("## PLAN \(label): buy-in \(dollars(plan.buyInCents)), \(players) players, \(colors.joined(separator: "/"))")
    for o in plan.options {
        let rows = allChipColors.compactMap { c in o.counts[c].map { "\(c) \($0)x\(dollars(o.valuesCents[c]!))" } }.joined(separator: ", ")
        print("   [\(o.kind.rawValue)] \(rows)  => \(o.totalChips) chips, \(dollars(o.totalCents))")
    }
    if let f = plan.failure { print("   failure: \(f)") }
    for a in plan.alternatives { print("   alternative: \(a.kind)") }
}

show("A", buyIn: 25, players: 6, colors: allChipColors)
show("B", buyIn: 20, players: 4, colors: ["White", "Red", "Blue"])
show("C", buyIn: 50, players: 8, colors: allChipColors)
show("D", buyIn: 100, players: 10, colors: allChipColors)
show("E", buyIn: 10, players: 2, colors: ["White", "Red"])
show("F", buyIn: 20, players: 5, colors: ["White", "Red", "Blue", "Green"])
show("G-nickel", buyIn: 25.03, players: 6, colors: ["White", "Red", "Blue"])
show("H-odd cents", buyIn: 19.95, players: 6, colors: allChipColors)
show("I-tiny", buyIn: 1.35, players: 6, colors: ["White", "Green", "Black"])
show("J-floor5", buyIn: 3.15, players: 6, colors: allChipColors)
show("K-below floor", buyIn: 3.10, players: 6, colors: allChipColors)
show("L-one colour", buyIn: 25, players: 6, colors: ["Red"])
show("M-one colour odd", buyIn: 13, players: 6, colors: ["Blue"])
print("")
print("-- players vs target (50 dollars, all colours):")
for p in [2, 4, 6, 8, 10] { show("P\(p)", buyIn: 50, players: p, colors: allChipColors) }
print("")
showPlan("no inventory", buyIn: 25, players: 6, colors: allChipColors)
showPlan("20 W/R/B", buyIn: 20, players: 4, colors: ["White", "Red", "Blue"])
let inv100 = ChipInventory.preset(.hundred, colors: ["White", "Red", "Blue", "Green", "Black"])
print("preset 100 over 5 colours: \(allChipColors.map { "\($0)=\(inv100.owned[$0]!)" }.joined(separator: " "))")
showPlan("100-set, 8 players, $50", buyIn: 50, players: 8, colors: allChipColors, inventory: inv100)
showPlan("100-set, 10 players, $100", buyIn: 100, players: 10, colors: allChipColors, inventory: inv100)
let inv100three = ChipInventory.preset(.hundred, colors: ["White", "Red", "Blue"])
print("preset 100 over 3 colours: \(["White", "Red", "Blue"].map { "\($0)=\(inv100three.owned[$0]!)" }.joined(separator: " "))")
showPlan("100-set 3 colours, 6 players, $20", buyIn: 20, players: 6, colors: ["White", "Red", "Blue"], inventory: inv100three)
showPlan("too small", buyIn: 2, players: 6, colors: allChipColors)
let printed = ChipInventory(owned: ["White": 200, "Red": 200, "Blue": 100], printedValues: ["White": 25, "Red": 100, "Blue": 500])
showPlan("printed values 0.25/1/5, $20", buyIn: 20, players: 4, colors: ["White", "Red", "Blue"], inventory: printed)
showPlan("printed values 0.25/1/5, $22.10", buyIn: 22.10, players: 4, colors: ["White", "Red", "Blue"], inventory: printed)
showPlan("locked Red=1.00", buyIn: 20, players: 4, colors: ["White", "Red", "Blue"], locked: ["Red": 100])
showPlan("locked conflict W=1.00,R=0.50", buyIn: 20, players: 4, colors: ["White", "Red", "Blue"], locked: ["White": 100, "Red": 50])
print("")
print("-- blinds:")
for (stack, smallest) in [(10_000, 25), (5_000, 25), (2_500, 5), (2_500, 25), (2_000, 25), (20_000, 25)] {
    if let b = BlindsPlanner.suggested(stackCents: stack, smallestChipCents: smallest) {
        print("   stack \(dollars(stack)), smallest chip \(dollars(smallest)) -> blinds \(dollars(b.smallMinor))/\(dollars(b.bigMinor)), \(BlindsPlanner.bigBlinds(inStackCents: stack, blinds: b)) big blinds")
    }
}
