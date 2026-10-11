//
//  PokerButton.swift
//  PokerChipApp
//
//  The app's buttons. One component with four intents, so a screen picks the
//  meaning (primary action, alternative, destructive, low-emphasis) rather
//  than styling a button by hand.
//

import SwiftUI

struct PokerButton: View {
    enum Kind {
        case primary, secondary, destructive, quiet
    }

    let title: String
    var systemImage: String? = nil
    var kind: Kind = .primary
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView().tint(kind == .primary ? .black : .pokerGoldLight)
                } else {
                    if let systemImage {
                        Image(systemName: systemImage).accessibilityHidden(true)
                    }
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PokerButtonStyle(kind: kind, isEnabled: isEnabled && !isLoading))
        .disabled(!isEnabled || isLoading)
    }
}

struct PokerButtonStyle: ButtonStyle {
    let kind: PokerButton.Kind
    var isEnabled = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let press = reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1)
        let pressAnimation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.15)

        switch kind {
        case .primary:
            configuration.label
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.black)
                .frame(minHeight: 54)
                .background(
                    LinearGradient(colors: [.pokerGoldLight, .pokerGold], startPoint: .top, endPoint: .bottom)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(press)
                .shadow(
                    color: Color.pokerGold.opacity(configuration.isPressed ? 0.15 : 0.35),
                    radius: configuration.isPressed ? 3 : 10,
                    y: 4
                )
                .animation(pressAnimation, value: configuration.isPressed)

        case .secondary:
            configuration.label
                .font(.headline)
                .foregroundStyle(Color.pokerPurpleLight)
                .frame(minHeight: 50)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.pokerPurpleLight.opacity(0.45), lineWidth: 1)
                )
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(press)
                .animation(pressAnimation, value: configuration.isPressed)

        case .destructive:
            configuration.label
                .font(.headline)
                .foregroundStyle(Color.pokerNegative)
                .frame(minHeight: 50)
                .background(Color.pokerNegative.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.pokerNegative.opacity(0.45), lineWidth: 1)
                )
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(press)
                .animation(pressAnimation, value: configuration.isPressed)

        case .quiet:
            configuration.label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.pokerGoldLight)
                .frame(minHeight: Spacing.minTapTarget)
                .contentShape(Rectangle())
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
        }
    }
}

extension View {
    /// The secondary-button look for a `NavigationLink` label, which can't
    /// take a ButtonStyle.
    func pokerSecondaryLabel() -> some View {
        font(.headline)
            .foregroundStyle(Color.pokerPurpleLight)
            .frame(minHeight: 50)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.pokerPurpleLight.opacity(0.45), lineWidth: 1)
            )
    }
}
