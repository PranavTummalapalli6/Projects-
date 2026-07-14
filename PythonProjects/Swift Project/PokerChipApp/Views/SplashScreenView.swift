//
//  SplashScreenView.swift
//  PokerChipApp
//
//  Created by Pranav on 4/2/25.
//

import SwiftUI

struct SplashScreenView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var splashFinished = false

    var body: some View {
        Group {
            if splashFinished {
                if authViewModel.isSignedIn {
                    StartScreenView()
                } else {
                    AuthenticationView()
                }
            } else {
                VStack {
                    Image("StudioLogo")
                        .resizable()
                        .scaledToFit()
                        .padding(40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .ignoresSafeArea()
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation {
                            splashFinished = true
                        }
                    }
                }
            }
        }
    }
}

struct SplashScreenView_Previews: PreviewProvider {
    static var previews: some View {
        SplashScreenView()
            .environmentObject(AuthViewModel())
    }
}

