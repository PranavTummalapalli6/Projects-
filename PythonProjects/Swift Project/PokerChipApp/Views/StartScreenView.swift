//
//  StartScreenView.swift
//  PokerChipApp
//
//  Created by Pranav on 4/2/25.
//

import SwiftUI

struct StartScreenView: View {
    var body: some View {
        VStack {
            Image("poker_chip_counter_no_bg")
                .resizable()
                .scaledToFit()
                .frame(height: 150)
            Text("Poker Chip Counter")
                .font(.largeTitle)
                .bold()
            NavigationLink("Start", destination: BuyInView())
                .padding()
        }
    }
}

struct StartScreenView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            StartScreenView()
        }
    }
}
