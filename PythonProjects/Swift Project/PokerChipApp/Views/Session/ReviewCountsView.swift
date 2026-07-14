//
//  ReviewCountsView.swift
//  PokerChipApp
//
//  Mandatory confirmation step: automatic chip detection from a single photo
//  cannot be guaranteed accurate (stacked/overlapping chips are genuinely hard),
//  so the suggested counts are always shown as editable and the user must confirm
//  before a result is calculated.
//

import SwiftUI

struct ReviewCountsView: View {
    let buyIn: Double
    let denominations: [String: Double]
    let elapsedSeconds: Int
    let sessionId: String
    let confidence: String?
    let photoUrl: String?

    @State private var counts: [String: String]
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var result: SessionResult?

    private let chipColors = ["White", "Red", "Blue", "Green", "Black"]

    init(
        buyIn: Double,
        denominations: [String: Double],
        elapsedSeconds: Int,
        sessionId: String,
        suggestedCounts: [String: Int]?,
        confidence: String?,
        photoUrl: String?
    ) {
        self.buyIn = buyIn
        self.denominations = denominations
        self.elapsedSeconds = elapsedSeconds
        self.sessionId = sessionId
        self.confidence = confidence
        self.photoUrl = photoUrl

        var initial: [String: String] = [:]
        for color in ["White", "Red", "Blue", "Green", "Black"] {
            if let suggested = suggestedCounts?[color] {
                initial[color] = String(suggested)
            } else {
                initial[color] = ""
            }
        }
        _counts = State(initialValue: initial)
    }

    private var estimatedEndingValue: Double {
        chipColors.reduce(0) { total, color in
            let count = Double(counts[color] ?? "") ?? 0
            let value = denominations[color] ?? 0
            return total + count * value
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                confidenceBanner

                Text("Confirm Final Chip Counts")
                    .font(.title3.bold())

                VStack(spacing: 10) {
                    ForEach(chipColors, id: \.self) { color in
                        HStack {
                            Circle()
                                .fill(chipColor(color))
                                .frame(width: 20, height: 20)
                            Text(color)
                                .frame(width: 60, alignment: .leading)
                            Text(denominations[color].map { String(format: "$%.2f", $0) } ?? "—")
                                .foregroundColor(.secondary)
                                .frame(width: 55, alignment: .leading)
                            TextField("0", text: binding(for: color))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                }

                HStack {
                    Text("Ending Value")
                        .font(.headline)
                    Spacer()
                    Text(String(format: "$%.2f", estimatedEndingValue))
                        .font(.headline)
                }
                .padding()
                .background(Color.gray.opacity(0.12))
                .cornerRadius(12)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.orange)
                }

                Button {
                    submit()
                } label: {
                    ZStack {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Calculate Result").font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(height: 55)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .disabled(isSubmitting)
            }
            .padding()
        }
        .navigationTitle("Review Counts")
        .navigationDestination(item: $result) { result in
            ResultView(
                buyIn: buyIn,
                profitLoss: result.profitLoss,
                elapsedSeconds: elapsedSeconds,
                counts: finalCountsInt(),
                denominations: denominations,
                photoUrl: result.photoUrl
            )
        }
    }

    @ViewBuilder
    private var confidenceBanner: some View {
        if let confidence {
            Label(confidenceMessage(confidence), systemImage: "wand.and.stars")
                .font(.footnote)
                .foregroundColor(.yellow)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.15))
                .cornerRadius(10)
        } else {
            Label("Automatic detection wasn't available — enter your final counts.", systemImage: "hand.tap")
                .font(.footnote)
                .foregroundColor(.orange)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(10)
        }
    }

    private func binding(for color: String) -> Binding<String> {
        Binding(
            get: { counts[color] ?? "" },
            set: { counts[color] = $0 }
        )
    }

    private func finalCountsInt() -> [String: Int] {
        chipColors.reduce(into: [String: Int]()) { dict, color in
            dict[color] = Int(counts[color] ?? "") ?? 0
        }
    }

    private func confidenceMessage(_ confidence: String) -> String {
        switch confidence {
        case "high": return "Auto-detected with high confidence — please double check before continuing."
        case "medium": return "Auto-detected, but some chips may be miscounted — please verify."
        default: return "Auto-detection had low confidence here (stacked/overlapping chips) — please correct the counts below."
        }
    }

    private func chipColor(_ name: String) -> Color {
        switch name {
        case "White": return Color(white: 0.92)
        case "Red": return .red
        case "Blue": return .blue
        case "Green": return .green
        case "Black": return .black
        default: return .gray
        }
    }

    private func submit() {
        errorMessage = nil
        isSubmitting = true
        Task {
            let finalCounts = finalCountsInt()
            do {
                let sessionResult = try await ChipVisionAPIClient.shared.completeSession(
                    sessionId: sessionId,
                    buyIn: buyIn,
                    denominations: denominations,
                    finalCounts: finalCounts,
                    elapsedSeconds: elapsedSeconds
                )
                result = sessionResult
            } catch {
                // The result is still shown even if saving to the backend fails —
                // the user should never be blocked from seeing their own math.
                errorMessage = "Couldn't save this session to the server (\(error.localizedDescription)). Showing your result locally."
                result = SessionResult(profitLoss: estimatedEndingValue - buyIn, photoUrl: photoUrl ?? "")
            }
            isSubmitting = false
        }
    }
}

struct ReviewCountsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ReviewCountsView(
                buyIn: 50,
                denominations: ["White": 0.25, "Red": 1, "Blue": 2, "Green": 5, "Black": 10],
                elapsedSeconds: 5400,
                sessionId: "preview",
                suggestedCounts: ["White": 12, "Red": 8, "Blue": 3, "Green": 1, "Black": 0],
                confidence: "medium",
                photoUrl: nil
            )
        }
    }
}
