//
//  ResultView.swift
//  PokerChipApp
//

import SwiftUI

struct ResultView: View {
    let buyIn: Double
    let profitLoss: Double
    let elapsedSeconds: Int
    let counts: [String: Int]
    let denominations: [String: Double]
    let photoUrl: String

    @Environment(\.dismiss) private var dismiss

    private let chipColors = ["White", "Red", "Blue", "Green", "Black"]

    private var isProfit: Bool { profitLoss >= 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text(isProfit ? "You're Up!" : "You're Down")
                        .font(.title.bold())
                        .foregroundColor(isProfit ? .green : .red)

                    Text((isProfit ? "+$" : "-$") + String(format: "%.2f", abs(profitLoss)))
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundColor(isProfit ? .green : .red)
                }
                .padding(.top, 20)

                VStack(spacing: 10) {
                    resultRow("Buy-In", String(format: "$%.2f", buyIn))
                    Divider()
                    resultRow("Ending Value", String(format: "$%.2f", buyIn + profitLoss))
                    Divider()
                    resultRow("Time Played", formatTime(elapsedSeconds))
                }
                .padding()
                .background(Color.gray.opacity(0.12))
                .cornerRadius(16)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Final Chip Breakdown")
                        .font(.headline)
                    ForEach(chipColors, id: \.self) { color in
                        if let count = counts[color], count > 0 {
                            HStack {
                                Circle()
                                    .fill(chipColor(color))
                                    .frame(width: 14, height: 14)
                                Text(color)
                                Spacer()
                                Text("\(count) × \(String(format: "$%.2f", denominations[color] ?? 0))")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.12))
                .cornerRadius(16)

                VStack(spacing: 12) {
                    Button {
                        // Pops back to ReviewCountsView with its previously entered
                        // counts still filled in, ready to correct and resubmit —
                        // the fix for a miscounted chip, not a whole new game.
                        dismiss()
                    } label: {
                        Text("That's Not Right — Edit Counts")
                            .font(.headline)
                            .foregroundStyle(.blue)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(12)
                    }

                    NavigationLink(destination: StartScreenView()) {
                        Text("Play Again")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(height: 55)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Result")
    }

    private func resultRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).bold()
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

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct ResultView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ResultView(
                buyIn: 50,
                profitLoss: 13,
                elapsedSeconds: 5400,
                counts: ["White": 12, "Red": 8, "Blue": 3, "Green": 1, "Black": 0],
                denominations: ["White": 0.25, "Red": 1, "Blue": 2, "Green": 5, "Black": 10],
                photoUrl: ""
            )
        }
    }
}
