//
//  ChipView.swift
//  PokerChipApp
//
//  A top-down vector poker chip: edge spots, an inner ring, an optional value
//  label. Used everywhere a chip colour appears, so a "red chip" looks like
//  the same object on every screen.
//

import SwiftUI

struct ChipView: View {
    let color: String
    var size: CGFloat = 44
    /// Text on the chip face (e.g. "$0.25"). Only shown at sizes big enough to read.
    var label: String? = nil
    var isDimmed = false
    /// Force the colour-independent letter on or off. By default it follows
    /// the "Differentiate Without Color" system setting and the in-app
    /// colour-blind option.
    var showsCue: Bool? = nil

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @AppStorage(PrefKey.colorBlindChips) private var colorBlindChips = false

    private var cueVisible: Bool {
        showsCue ?? (differentiateWithoutColor || colorBlindChips)
    }

    private var centerText: String? {
        if let label, size >= 40 { return label }
        if cueVisible { return ChipPalette.initial(color) }
        return nil
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [ChipPalette.fill(color).opacity(0.78), ChipPalette.fill(color)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ForEach(0..<8, id: \.self) { index in
                RoundedRectangle(cornerRadius: size * 0.03, style: .continuous)
                    .fill(ChipPalette.spot(color))
                    .frame(width: size * 0.17, height: size * 0.10)
                    .offset(y: -size * 0.425)
                    .rotationEffect(.degrees(Double(index) * 45))
            }

            Circle()
                .strokeBorder(ChipPalette.spot(color).opacity(0.65), lineWidth: max(1, size * 0.025))
                .padding(size * 0.22)

            if let centerText {
                Text(centerText)
                    .font(.system(size: size * (label == nil ? 0.30 : 0.20), weight: .heavy, design: .rounded))
                    .foregroundStyle(ChipPalette.label(color))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(size * 0.26)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(ChipPalette.rim(color), lineWidth: max(1, size * 0.03)))
        .shadow(color: .black.opacity(0.35), radius: size * 0.05, y: size * 0.04)
        .opacity(isDimmed ? 0.3 : 1)
        .scaleEffect(isDimmed ? 0.92 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(color) chip")
    }
}

struct ChipView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                ForEach(allChipColors, id: \.self) { ChipView(color: $0, size: 56, showsCue: true) }
            }
            HStack(spacing: 12) {
                ForEach(allChipColors, id: \.self) { ChipView(color: $0, size: 44) }
            }
            HStack(spacing: 12) {
                ForEach(allChipColors, id: \.self) { ChipView(color: $0, size: 34, isDimmed: true) }
            }
        }
        .padding()
        .background(PokerBackground())
    }
}
