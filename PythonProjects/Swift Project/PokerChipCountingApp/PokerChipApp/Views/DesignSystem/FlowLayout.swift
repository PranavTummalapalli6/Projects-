//
//  FlowLayout.swift
//  PokerChipApp
//
//  Quick-pick chips that wrap onto as many lines as they need — names of
//  different lengths, at any text size, without a fixed number of columns.
//

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = Spacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > available {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// One tappable suggestion: a gold-tinted capsule, at least 44 pt tall.
struct QuickPickChip: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption.weight(.bold)).accessibilityHidden(true)
                }
                Text(title)
                    .font(.pokerFootnote.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.pokerGoldLight)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: Spacing.minTapTarget)
            .background(Color.pokerGold.opacity(0.12))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
