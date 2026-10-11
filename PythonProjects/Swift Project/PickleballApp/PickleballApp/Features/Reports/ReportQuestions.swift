import PickleCore
import SwiftUI

/// A single, context-chosen question with large icon answers. One tap answers it.
struct ReportQuestion: Identifiable {
    struct Option: Identifiable {
        var symbol: String
        var label: String
        var value: String
        var tint: Color
        var id: String { value }
    }

    var kind: PromptKind
    var title: String
    var options: [Option]
    var id: PromptKind { kind }

    var reportKind: LiveReportKind? {
        switch kind {
        case .howBusy: .occupancy
        case .paddleWait: .paddleStack
        case .courtSurface: .surface
        case .confirmExists: nil
        }
    }

    static func make(_ kind: PromptKind) -> ReportQuestion {
        switch kind {
        case .howBusy:
            return ReportQuestion(kind: kind, title: "How busy is it?", options: [
                .init(symbol: Icons.occupancy(.courtsOpen), label: "Courts open", value: OccupancyStatus.courtsOpen.rawValue, tint: Theme.available),
                .init(symbol: Icons.occupancy(.mostlyFull), label: "Mostly full", value: OccupancyStatus.mostlyFull.rawValue, tint: Theme.moderate),
                .init(symbol: Icons.occupancy(.allFull), label: "All full", value: OccupancyStatus.allFull.rawValue, tint: Theme.busy),
                .init(symbol: Icons.occupancy(.playersWaiting), label: "Players waiting", value: OccupancyStatus.playersWaiting.rawValue, tint: Theme.unavailable),
            ])
        case .paddleWait:
            return ReportQuestion(kind: kind, title: "Paddle wait?", options: [
                .init(symbol: Icons.paddle(.none), label: "None", value: PaddleStackLevel.none.rawValue, tint: Theme.available),
                .init(symbol: Icons.paddle(.short), label: "Short", value: PaddleStackLevel.short.rawValue, tint: Theme.moderate),
                .init(symbol: Icons.paddle(.medium), label: "Medium", value: PaddleStackLevel.medium.rawValue, tint: Theme.busy),
                .init(symbol: Icons.paddle(.long), label: "Long", value: PaddleStackLevel.long.rawValue, tint: Theme.unavailable),
            ])
        case .courtSurface:
            return ReportQuestion(kind: kind, title: "Court surface?", options: [
                .init(symbol: Icons.surface(.dry), label: "Dry", value: SurfaceCondition.dry.rawValue, tint: Theme.available),
                .init(symbol: Icons.surface(.slightlyDamp), label: "Damp", value: SurfaceCondition.slightlyDamp.rawValue, tint: Theme.moderate),
                .init(symbol: Icons.surface(.wet), label: "Wet", value: SurfaceCondition.wet.rawValue, tint: Theme.surfaceIssue),
                .init(symbol: Icons.surface(.debris), label: "Debris", value: SurfaceCondition.debris.rawValue, tint: Theme.busy),
            ])
        case .confirmExists:
            return ReportQuestion(kind: kind, title: "Is this court here?", options: [
                .init(symbol: "checkmark.circle.fill", label: "Yes", value: "yes", tint: Theme.available),
                .init(symbol: "xmark.circle.fill", label: "No", value: "no", tint: Theme.unavailable),
            ])
        }
    }
}

/// 2×2 (or 1×2) grid of large answer tiles.
struct QuestionTiles: View {
    let question: ReportQuestion
    var selected: String?
    var disabled = false
    let onAnswer: (ReportQuestion.Option) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(question.options) { option in
                ChoiceTile(symbol: option.symbol, label: option.label, tint: option.tint, isSelected: selected == option.value) {
                    onAnswer(option)
                }
                .disabled(disabled)
                .accessibilityIdentifier("answer_\(option.value)")
            }
        }
    }
}

/// Shared submit logic for prompt card and report sheet.
@MainActor
enum QuickAnswer {
    static func submit(_ option: ReportQuestion.Option, question: ReportQuestion, facility: Facility,
                       reports: ReportService, prompted: Bool) async -> (ok: Bool, message: String) {
        do {
            if question.kind == .confirmExists {
                let r = try await reports.confirm(facility, exists: option.value == "yes")
                return (r.accepted, r.accepted ? "Thanks for confirming." : "We couldn't save that.")
            }
            guard let kind = question.reportKind else { return (false, "") }
            let r = try await reports.submit(kind, value: option.value, at: facility, promptKind: prompted ? question.kind : nil)
            return (r.accepted, r.userMessage)
        } catch {
            return (false, (error as? LocalizedError)?.errorDescription ?? "We couldn't save that report.")
        }
    }
}
