import SwiftUI

/// Explains the benefit before the system prompt appears. Shown once; "Not now" never nags again.
struct LocationPrimerView: View {
    let onAllow: () -> Void
    let onSearchInstead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "location.circle.fill").font(.system(size: 36)).foregroundStyle(Theme.accent)
                Text("Find courts near you").font(.title3.weight(.bold))
            }
            Text("Use your location to find nearby courts and verify live court reports. We never keep a location history.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Use my location", action: onAllow)
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("allowLocation")
            Button("Not now — I'll search instead", action: onSearchInstead)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        .padding(.horizontal, 16)
    }
}
