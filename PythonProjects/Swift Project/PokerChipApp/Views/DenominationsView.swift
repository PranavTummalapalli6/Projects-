//
//  DenominationsView.swift
//  PokerChipApp
//
//  Created by Pranav on 4/2/25.
//

import SwiftUI
import UIKit

// MARK: - Default Denomination Views

func getDynamicDenominations(buyIn: Double) -> [String: Double] {
    let selectedDenominations: [Double]
    
    if buyIn <= 5 {
        selectedDenominations = [0.05, 0.10, 0.25, 0.50, 1]
    } else if buyIn <= 10 {
        selectedDenominations = [0.10, 0.25, 0.50, 1, 2]
    } else if buyIn <= 50 {
        selectedDenominations = [0.25, 1, 2, 5, 10]
    } else if buyIn <= 100 {
        selectedDenominations = [0.50, 1, 5, 10, 25]
    } else {
        selectedDenominations = [1, 5, 10, 25, 50]
    }

    var chipValues: [String: Double] = [:]
    let chipColors = ["White", "Red", "Blue", "Green", "Black"]
    
    for (index, color) in chipColors.enumerated() {
        let chipDenomination = selectedDenominations[min(index, selectedDenominations.count - 1)]
        chipValues[color] = chipDenomination
    }
    
    return chipValues
}


/// This function replicates the Python algorithm for calculating chip distribution.
/// It returns an optional solution (a dictionary mapping chip color to count)
/// and a dictionary of chip values.
func calculateFlexibleChipDistribution(buyIn: Double, players: Int) -> ([String: Int]?, [String: Double]) {
    let integerBuyIn = Int(buyIn)
    let integerPlayers = players
    var n: [Int: Double] = [:]
    
    if integerBuyIn < 10 {
        n[1] = Double(integerBuyIn) / 100.0
        n[2] = (Double(integerBuyIn) / 100.0) * 2.0
    } else {
        n[1] = (Double(integerBuyIn) / 100.0) / 2.0
        n[2] = Double(integerBuyIn) / 100.0
    }
    for i in 3...5 {
        if i % 5 == 0 {
            n[i] = n[i - 1]! * 2.0
        } else if i % 2 == 0 {
            n[i] = n[i - 1]! * 2.0
        } else if i % 2 == 1 {
            n[i] = n[i - 1]! * 2.5
        }
    }
    
    // Constraints (chip limits per player)
    let maxW = min(100 / integerPlayers, 15)
    let maxR = 50 / integerPlayers
    let maxB = 50 / integerPlayers
    let maxG = 50 / integerPlayers
    let maxBl = 50 / integerPlayers
    
    var bestSolution: [String: Int]? = nil
    var minScore = Double.infinity
    
    // Loop over possible white chip counts.
    for w in 1...maxW {
        let rTarget = Double(w) / 2.0
        let bTarget = Double(w) / 4.0
        let gTarget = Double(w) / 8.0
        let blTarget = Double(w) / 16.0
        
        let rStart = max(1, Int(floor(rTarget)) - 1)
        let rEnd = min(maxR, Int(ceil(rTarget)) + 1)
        for r in rStart...rEnd {
            let bStart = max(1, Int(floor(bTarget)) - 1)
            let bEnd = min(maxB, Int(ceil(bTarget)) + 1)
            for b in bStart...bEnd {
                let gStart = max(1, Int(floor(gTarget)) - 1)
                let gEnd = min(maxG, Int(ceil(gTarget)) + 1)
                for g in gStart...gEnd {
                    let blStart = max(1, Int(floor(blTarget)) - 1)
                    let blEnd = min(maxBl, Int(ceil(blTarget)) + 1)
                    for bl in blStart...blEnd {
                        // Ensure descending (or nonincreasing) order.
                        if !(w >= r && r >= b && b >= g && g >= bl) {
                            continue
                        }
                        let totalValue = Double(w) * n[1]! +
                                         Double(r) * n[2]! +
                                         Double(b) * n[3]! +
                                         Double(g) * n[4]! +
                                         Double(bl) * n[5]!
                        let diff = abs(totalValue - Double(integerBuyIn))
                        let trendDeviation = abs(Double(r) - rTarget) +
                                             abs(Double(b) - bTarget) +
                                             abs(Double(g) - gTarget) +
                                             abs(Double(bl) - blTarget)
                        let score = diff + trendDeviation
                        if score < minScore {
                            minScore = score
                            bestSolution = ["White": w, "Red": r, "Blue": b, "Green": g, "Black": bl]
                        }
                    }
                }
            }
        }
    }
    
    let chipValues: [String: Double] = [
        "White": n[1]!,
        "Red": n[2]!,
        "Blue": n[3]!,
        "Green": n[4]!,
        "Black": n[5]!
    ]
    
    return (bestSolution, chipValues)
}


// MARK: - Custom Denomination View

struct CustomDenominationView: View {
    @State private var whiteCount = ""
    @State private var whiteValue = ""
    @State private var redCount = ""
    @State private var redValue = ""
    @State private var blueCount = ""
    @State private var blueValue = ""
    @State private var greenCount = ""
    @State private var greenValue = ""
    @State private var blackCount = ""
    @State private var blackValue = ""
    
    var buyIn: Double
    let maxChipsPerColor = 50
    let players = 5 // Replace with dynamic input if needed
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter Chip Counts and Values in Dollars")
                .font(.headline)
            
            ForEach(["White", "Red", "Blue", "Green", "Black"], id: \.self) { color in
                HStack {
                    TextField("\(color) Count", text: binding(for: color, isCount: true))
                        .keyboardType(.numberPad)
                    TextField("\(color) Value", text: binding(for: color, isCount: false))
                        .keyboardType(.decimalPad)
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if let warning = warningMessage(for: color) {
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()

            if allValuesEntered {
                HStack {
                    Spacer()
                    NavigationLink("Start Timer", destination: TimerView(buyIn: buyIn, denominations: enteredDenominations))
                        .padding()
                    Spacer()
                }
            } else {
                Text("Enter a value for every chip color to continue")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
    }

    var enteredDenominations: [String: Double] {
        var dict: [String: Double] = [:]
        if let v = Double(whiteValue) { dict["White"] = v }
        if let v = Double(redValue) { dict["Red"] = v }
        if let v = Double(blueValue) { dict["Blue"] = v }
        if let v = Double(greenValue) { dict["Green"] = v }
        if let v = Double(blackValue) { dict["Black"] = v }
        return dict
    }

    var allValuesEntered: Bool {
        enteredDenominations.count == 5
    }

    func binding(for color: String, isCount: Bool) -> Binding<String> {
        switch (color, isCount) {
        case ("White", true): return $whiteCount
        case ("White", false): return $whiteValue
        case ("Red", true): return $redCount
        case ("Red", false): return $redValue
        case ("Blue", true): return $blueCount
        case ("Blue", false): return $blueValue
        case ("Green", true): return $greenCount
        case ("Green", false): return $greenValue
        case ("Black", true): return $blackCount
        case ("Black", false): return $blackValue
        default: return .constant("")
        }
    }
    
    func warningMessage(for color: String) -> String? {
        guard let count = Int(binding(for: color, isCount: true).wrappedValue),
              let value = Double(binding(for: color, isCount: false).wrappedValue) else {
            return "Invalid number or value"
        }
        
        let chipTotalValue = Double(count) * value
        let totalValue = totalCustomValue()
        
        if chipTotalValue + totalValue - chipTotalValue < buyIn {
            return "Total value is less than buy-in"
        }
        if chipTotalValue + totalValue - chipTotalValue > buyIn {
            return "Total value exceeds buy-in"
        }
        if count * players > maxChipsPerColor {
            return "Too many chips for \(color) per player"
        }
        return nil
    }
    
    func totalCustomValue() -> Double {
        let counts = [whiteCount, redCount, blueCount, greenCount, blackCount].compactMap { Int($0) }
        let values = [whiteValue, redValue, blueValue, greenValue, blackValue].compactMap { Double($0) }
        return zip(counts, values).map { Double($0) * $1 }.reduce(0, +)
    }
}


// MARK: - Timer and Camera Views

/// End-of-game screen: times the session, then hands the captured photo off to
/// ChipVisionService for detection before moving to the mandatory review step.
/// The photo itself is never persisted on-device — it's held in memory only for
/// the duration of the upload, then discarded (see ChipVisionAPIClient).
struct TimerView: View {
    let buyIn: Double
    let denominations: [String: Double]

    @State private var startTime = Date()
    @State private var elapsedTime = 0
    @State private var timer: Timer? = nil
    @State private var sessionId = UUID().uuidString
    @State private var isUploading = false
    @State private var uploadNotice: String?
    @State private var analysisOutcome: PhotoAnalysisOutcome?

    var body: some View {
        VStack(spacing: 20) {
            Text("Time Spent Playing Poker")
                .font(.headline)

            Text("🤑")
                .font(.system(size: 100))
                .padding(.bottom, 10)

            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 250, height: 120)
                .overlay(
                    Text(formatTime(elapsedTime))
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 5)
                        .overlay(
                            LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .top, endPoint: .bottom)
                                .mask(
                                    Text(formatTime(elapsedTime))
                                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                                )
                        )
                )
                .padding()

            if isUploading {
                ProgressView("Analyzing photo…")
                    .padding()
            } else {
                CameraViewWrapper(onCapture: handleCapture)
                    .padding(.horizontal)
            }

            if let uploadNotice {
                Text(uploadNotice)
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
        .onAppear { startTimer() }
        .navigationDestination(item: $analysisOutcome) { outcome in
            ReviewCountsView(
                buyIn: buyIn,
                denominations: denominations,
                elapsedSeconds: elapsedTime,
                sessionId: sessionId,
                suggestedCounts: outcome.counts,
                confidence: outcome.confidence,
                photoUrl: outcome.photoUrl
            )
        }
    }

    private func handleCapture(_ image: UIImage) {
        stopTimer()
        isUploading = true
        uploadNotice = nil
        Task {
            do {
                let result = try await ChipVisionAPIClient.shared.uploadPhoto(
                    image: image,
                    denominations: denominations,
                    sessionId: sessionId
                )
                analysisOutcome = PhotoAnalysisOutcome(
                    counts: result.counts,
                    confidence: result.confidence,
                    photoUrl: result.photoUrl
                )
            } catch {
                // Never block the user on the vision service being unreachable —
                // fall through to manual entry on the same review screen.
                uploadNotice = "Couldn't reach the analysis service (\(error.localizedDescription)). Enter your counts manually on the next screen."
                analysisOutcome = PhotoAnalysisOutcome(counts: nil, confidence: nil, photoUrl: nil)
            }
            isUploading = false
        }
    }

    private func startTimer() {
        timer?.invalidate()
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime = Int(Date().timeIntervalSince(startTime))
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct CameraViewWrapper: View {
    var onCapture: (UIImage) -> Void
    @State private var showCamera = false

    var body: some View {
        Button {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                showCamera = true
            } else {
                print("Camera not available")
            }
        } label: {
            Label("Take Picture", systemImage: "camera.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(height: 55)
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .cornerRadius(12)
        }
        .sheet(isPresented: $showCamera) {
            CameraView(onCapture: onCapture)
        }
    }
}

/// Wraps UIImagePickerController's camera source. Unlike the original skeleton,
/// this actually extracts the captured UIImage and hands it back to the caller —
/// it never writes the image to disk or the Photos library itself.
struct CameraView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

struct CombinedDenominationsView: View {
    var buyIn: Double
    var players: Int
    
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 30) {
                let defaultDenominations = getDynamicDenominations(buyIn: buyIn)
                let chipColors = ["White", "Red", "Blue", "Green", "Black"]
                let percentages: [String: Double] = [
                    "White": 0.10, "Red": 0.10, "Blue": 0.20, "Green": 0.40, "Black": 0.20
                ]
                
                let defaultChipCounts = Dictionary(uniqueKeysWithValues: chipColors.map { color in
                    if let denomination = defaultDenominations[color], let percentage = percentages[color] {
                        var chipCount = Int(round(buyIn * percentage / denomination))
                        chipCount = min(chipCount, 10)
                        chipCount = max(chipCount, 1)
                        return (color, chipCount)
                    } else {
                        return (color, 1)
                    }
                })
                
                NavigationLink(destination: TimerView(buyIn: buyIn, denominations: defaultDenominations)) {
                    VStack(alignment: .center, spacing: 8) {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.yellow)
                        
                        Text("Default Denominations")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundColor(.red)
                        
                        ForEach(chipColors, id: \.self) { color in
                            if let value = defaultDenominations[color], let count = defaultChipCounts[color] {
                                Text("\(color): \(String(format: "%.2f", value)), Count: \(count)")
                                    .font(.system(size: 18, weight: .medium, design: .rounded))
                                    .foregroundColor(.yellow)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red, lineWidth: 2)
                    )
                }
                
                let (trendResult, trendChipValues) = calculateFlexibleChipDistribution(buyIn: buyIn, players: players)
                
                if let solution = trendResult {
                    NavigationLink(destination: TimerView(buyIn: buyIn, denominations: trendChipValues)) {
                        VStack(alignment: .center, spacing: 8) {
                            Image(systemName: "waveform.path.ecg.rectangle")
                                .resizable()
                                .frame(width: 50, height: 40)
                                .foregroundColor(.yellow)
                            
                            Text("Trend Default Denominations")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundColor(.red)
                            
                            ForEach(chipColors, id: \.self) { color in
                                if let count = solution[color], let value = trendChipValues[color] {
                                    Text("\(color): \(String(format: "%.2f", value)), Count: \(count)")
                                        .font(.system(size: 18, weight: .medium, design: .rounded))
                                        .foregroundColor(.yellow)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red, lineWidth: 2)
                        )
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Choose Denominations")
        .background(Color.black.edgesIgnoringSafeArea(.all))
    }
}
