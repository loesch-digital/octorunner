import DesignSystem
import SwiftUI
import SyncKit

struct RunnerLabelEditor: View {
    @Environment(\.locale) private var locale

    @Binding var editableLabels: [String]
    @Binding var newLabelInput: String
    let canEditLabels: Bool
    let review: RunnerRemoteLabelReview?
    let showReview: (RunnerRemoteLabelReview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("Assigned Labels (Matched by Workflow 'runs-on:')", locale: locale))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if let review {
                Button { showReview(review) } label: {
                    Label { Text("Review GitHub Labels…", bundle: .module) } icon: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .accessibilityHint(Text("Reviews different labels before applying them to OctoRunner.", bundle: .module))
                .disabled(!canEditLabels)
            }

            labelChips
            newLabelControl
        }
    }

    private var labelChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(editableLabels, id: \.self) { label in
                    HStack(spacing: 4) {
                        Text(label)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        if label.lowercased() != "self-hosted" {
                            Button {
                                removeLabel(label)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 5))
                }
            }
        }
        .scrollIndicators(.hidden)
        .disabled(!canEditLabels)
    }

    private var newLabelControl: some View {
        HStack(spacing: 8) {
            TextField(AppLocalization.string("Add capability label (e.g. fastlane, ios-18, xcode-27)…", locale: locale), text: $newLabelInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit(addCustomLabel)

            Button(AppLocalization.string("Add Label", locale: locale), systemImage: "plus", action: addCustomLabel)
                .buttonStyle(.bordered)
                .disabled(newLabelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .disabled(!canEditLabels)
    }

    private func addCustomLabel() {
        let trimmed = newLabelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !editableLabels.contains(trimmed) {
            editableLabels.append(trimmed)
        }
        newLabelInput = ""
    }

    private func removeLabel(_ label: String) {
        editableLabels.removeAll { $0 == label }
    }
}
