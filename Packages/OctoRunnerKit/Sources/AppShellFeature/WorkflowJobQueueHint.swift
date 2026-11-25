import DesignSystem
import SwiftUI

struct WorkflowJobQueueHint: View {
    @Environment(\.locale) private var locale
    let diagnosis: WorkflowJobQueueDiagnosis

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let age = diagnosis.jobAge {
                let elapsed = Duration.seconds(age)
                    .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)
                        .locale(locale))
                Text("Job created \(elapsed) ago", bundle: .module)
                    .fontWeight(.medium)
            }
            Text(AppLocalization.string(reasonKey, locale: locale))
            ForEach(diagnosis.runners) { runner in
                Text(verbatim: "\(runner.name) · \(AppLocalization.string(stateKey(runner.state), locale: locale))")
            }
        }
        .font(.caption)
        .foregroundStyle(OctoTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    private var reasonKey: String.LocalizationValue {
        switch diagnosis.reason {
        case .staleJob: "The last job observation is out of date. Refresh to check whether it is still queued."
        case .runnerStatusUnavailable: "Current status for matching repository runners is unavailable."
        case .noKnownMatch: "None of the observed repository runners match all the requested labels."
        case .idleMatch: "An observed runner with matching labels is idle. The reason for the wait is unknown."
        case .busyOrOffline: "The observed matches below are busy or offline."
        }
    }

    private func stateKey(_ state: WorkflowJobQueueDiagnosis.Runner.State) -> String.LocalizationValue {
        switch state {
        case .idle: "Queue runner idle"
        case .busy: "Queue runner busy"
        case .offline: "Queue runner offline"
        }
    }
}
