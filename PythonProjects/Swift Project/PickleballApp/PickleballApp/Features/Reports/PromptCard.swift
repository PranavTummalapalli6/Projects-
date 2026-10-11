import PickleCore
import SwiftUI

/// Non-modal, dismissible one-question card shown on arrival at a facility. One tap. Done.
struct PromptCard: View {
    let prompt: VisitService.ActivePrompt
    let reports: ReportService
    let onFinish: (_ answered: Bool) -> Void

    @State private var selected: String?
    @State private var message: String?
    @State private var submitting = false

    private var question: ReportQuestion { .make(prompt.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt.facility.name).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Text(question.title).font(.title3.weight(.bold))
                }
                Spacer()
                if message == nil {
                    Button("Not now") { onFinish(false) }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("promptDismiss")
                }
            }
            if let message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.available)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .transition(.scale.combined(with: .opacity))
            } else {
                QuestionTiles(question: question, selected: selected, disabled: submitting) { option in
                    selected = option.value
                    submitting = true
                    Task {
                        let result = await QuickAnswer.submit(option, question: question, facility: prompt.facility,
                                                              reports: reports, prompted: true)
                        withAnimation(.spring) { message = result.ok ? "Thanks!" : result.message }
                        if result.ok { Haptics.success() } else { Haptics.warning() }
                        try? await Task.sleep(for: .seconds(1.6))
                        onFinish(true)
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("promptCard")
    }
}
