//
//  SplashScreenView.swift
//  PokerChipApp
//
//  Created by Pranav on 4/2/25.
//

import SwiftUI

/// The Van Arp Studios seal, shown once per app version. It is drawn exactly
/// like the system launch screen (same image, same size, same black) so the
/// hand-off from one to the other is invisible, and it never waits on anything
/// but its own short timer.
struct SplashScreenView: View {
    var onFinished: () -> Void = {}

    /// The launch image's size in points (270 pt = 540 px at 2x, 810 px at 3x).
    private let sealSize: CGFloat = 270

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("SplashSeal")
                .resizable()
                .frame(width: sealSize, height: sealSize)
                .accessibilityHidden(true)
        }
        .task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            onFinished()
        }
    }
}

struct SplashScreenView_Previews: PreviewProvider {
    static var previews: some View {
        SplashScreenView()
    }
}
