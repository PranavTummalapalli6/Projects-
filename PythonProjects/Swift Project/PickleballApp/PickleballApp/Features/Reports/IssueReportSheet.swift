import PickleCore
import SwiftUI

/// Negative operational reports. These propagate quickly as warnings but never delete a facility.
struct IssueReportSheet: View {
    let facility: Facility
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var submitting: IssueKind?
    @State private var done: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if let done {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Theme.available)
                            Text(done).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                            Text("Other players will see a warning. If others confirm, the facility is marked unavailable.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.top)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("What's wrong?").font(.title2.weight(.bold))
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(IssueKind.allCases) { kind in
                                ChoiceTile(symbol: kind.symbol, label: kind.label, tint: Theme.busy, isSelected: submitting == kind) {
                                    submit(kind)
                                }
                                .disabled(submitting != nil)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Theme.groupedBackground)
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func submit(_ kind: IssueKind) {
        submitting = kind
        Task {
            do {
                let r = try await env.reports.reportIssue(kind, at: facility, note: nil)
                done = r.accepted ? "Thanks — reported." : r.userMessage
                Haptics.success()
            } catch {
                done = (error as? LocalizedError)?.errorDescription ?? "We couldn't save that."
                Haptics.warning()
            }
        }
    }
}
