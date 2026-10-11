import PickleCore
import SwiftUI

/// Facility-level map marker: pickleball badge in the status color, a status glyph (so status is never
/// conveyed by color alone), and a compact wait label when we have a meaningful estimate.
struct FacilityMarkerView: View {
    let recommendation: FacilityRecommendation
    var isSelected = false

    private var status: FacilityStatus { FacilityStatus(recommendation) }

    private var waitLabel: String? {
        guard status.isPlayable, status != .unknown else { return nil }
        let w = recommendation.prediction.wait
        return w.high.map { "\(w.low)–\($0)m" } ?? "\(w.low)+m"
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(status.color.gradient)
                    .frame(width: 38, height: 38)
                    .overlay(Image(systemName: "figure.pickleball").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white))
                    .overlay(Circle().stroke(.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                Image(systemName: status.symbol)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(status.color)
                    .frame(width: 17, height: 17)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(status.color, lineWidth: 1.5))
                    .offset(x: 5, y: -4)
                if recommendation.facility.isCommunityReported {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(Theme.restricted, in: Circle())
                        .offset(x: -26, y: -4)
                }
            }
            if let waitLabel {
                Text(waitLabel)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .scaleEffect(isSelected ? 1.2 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var parts = [recommendation.facility.name, status.label]
        if status.isPlayable { parts.append("estimated wait \(recommendation.prediction.wait.label)") }
        if let reason = recommendation.eligibility.reason { parts.append(reason) }
        if recommendation.facility.isCommunityReported { parts.append("community-reported") }
        return parts.joined(separator: ", ")
    }
}

struct ClusterMarkerView: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.headline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Theme.accent.gradient, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            .accessibilityLabel("\(count) facilities. Double tap to zoom in.")
            .accessibilityAddTraits(.isButton)
    }
}
