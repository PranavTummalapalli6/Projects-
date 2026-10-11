import PickleCore
import SwiftUI

/// Bottom cards answering "Where should I play right now?" — labelled trade-offs, not one opaque winner.
struct RecommendationStrip: View {
    let picks: [FacilityRecommendation]
    let onSelect: (FacilityRecommendation) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(picks) { rec in
                    Button { onSelect(rec) } label: { RecommendationCard(rec: rec) }
                        .buttonStyle(PressableStyle())
                        .containerRelativeFrame(.horizontal) { width, _ in picks.count == 1 ? width - 32 : width * 0.84 }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
        }
        .scrollTargetBehavior(.viewAligned)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("recommendationStrip")
    }
}

struct RecommendationCard: View {
    let rec: FacilityRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(rec.badges.map(\.displayName).joined(separator: " · "))
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(rec.facility.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            HStack(spacing: 6) {
                let status = FacilityStatus(rec)
                Image(systemName: status.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(status.color, in: Circle())
                    .accessibilityLabel(status.label)
                if let travel = Format.travel(rec.travel) { Text(travel) }
                if rec.travel != nil { Text("•").foregroundStyle(.tertiary) }
                Text("\(rec.prediction.wait.label) wait")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            HStack(spacing: 6) {
                Text(rec.fit.headline ?? rec.fit.tradeoff ?? accessLine)
                    .lineLimit(1)
                Spacer(minLength: 4)
                ConfidenceIndicator(level: rec.prediction.confidence)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens court details")
    }

    private var accessLine: String {
        [rec.facility.access.accessType == .unknown ? nil : rec.facility.access.accessType.displayName, rec.costFit.label]
            .compactMap { $0 }.joined(separator: " • ")
    }
}
