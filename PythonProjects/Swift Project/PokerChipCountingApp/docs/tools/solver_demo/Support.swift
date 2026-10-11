//
//  Support.swift
//
//  The two things DenominationEngine.swift and BlindsPlanner.swift need from the rest of the app,
//  so they can be compiled on their own for solver_demo (see main.swift). Keep in step with
//  `allChipColors` in PokerChipApp/Views/Theme.swift and `Blinds` in Views/Nights/Model/GameNight.swift.
//

import Foundation

let allChipColors = ["White", "Red", "Blue", "Green", "Black"]
struct Blinds: Equatable { var smallMinor: Int; var bigMinor: Int }
