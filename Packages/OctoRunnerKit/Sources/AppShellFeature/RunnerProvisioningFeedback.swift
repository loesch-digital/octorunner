import DesignSystem
import SwiftUI

struct RunnerProvisioningFeedback: View {
    let progress: String?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let progress {
                HStack(alignment: .top, spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(progress)
                        .font(.callout.monospaced())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(OctoTheme.accentBlue)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 8))
            }
            if let errorMessage {
                Label {
                    Text(errorMessage)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)
                }
                .font(.callout)
                .foregroundStyle(OctoTheme.errorRed)
            }
        }
    }
}
