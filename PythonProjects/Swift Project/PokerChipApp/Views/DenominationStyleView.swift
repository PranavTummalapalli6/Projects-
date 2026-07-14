//
//  DenominationStyleView.swift
//  PokerChipApp
//
//  Created by Pranav on 4/2/25.
//

import SwiftUI

struct DenominationStyleView: View {
    var buyIn: Double
    var players: Int

    var body: some View {
        List {
            NavigationLink("Custom", destination: CustomDenominationView(buyIn: buyIn))
            NavigationLink("Default", destination: CombinedDenominationsView(buyIn: buyIn, players: players))
        }
        .navigationTitle("Denomination Style")
    }
}

struct DenominationStyleView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DenominationStyleView(buyIn: 50, players: 4)
        }
    }
}
