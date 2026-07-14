//
//  BuyInView.swift
//  PokerChipApp
//
//  Created by Pranav on 4/2/25.
//

import SwiftUI

struct BuyInView: View {
    @State private var buyInAmount = ""
    @State private var numPlayers = ""

    var body: some View {
        VStack {
            Text("Enter Buy-In Amount")
            TextField("Amount", text: $buyInAmount)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.decimalPad)
                .padding()
            Text("Enter the Number of Players")
            TextField("Players", text:$numPlayers)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)
                .padding()
            if let buyIn = Double(buyInAmount),
               let players = Int(numPlayers),
               buyIn > 0,
               players > 0 {
                NavigationLink("Next", destination: DenominationStyleView(buyIn: buyIn, players: players))
                    .padding()
            } else {
                Text("Please enter valid values")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
    }
}

struct BuyInView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BuyInView()
        }
    }
}
