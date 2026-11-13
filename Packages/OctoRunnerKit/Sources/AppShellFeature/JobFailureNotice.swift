import CoreModels
import DesignSystem
import SwiftUI

struct JobFailureNotice: View {
    @Environment(AppPreferencesStore.self) private var preferences
    @Environment(\.locale) private var locale
    let results: LocalJobResults

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Job results", bundle: .module).font(.caption.bold())
            Label(JobFailureNotice.title(results.unreviewedFailures.count, locale: locale), systemImage: "xmark.circle.fill")
                .foregroundStyle(OctoTheme.errorRed).font(.caption)
            Text("From loaded GitHub history; runner availability is separate.", bundle: .module)
                .font(.caption).foregroundStyle(OctoTheme.secondaryText)
            Button {
                preferences.reviewedJobFailures.formUnion(results.unreviewedFailures.map(LocalJobResults.reviewKey))
            } label: {
                Text("Mark these failures as reviewed", bundle: .module)
            }
            .font(.caption)
            .accessibilityHint(Text("Clears this alert without changing job results or runner status", bundle: .module))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
    }

    static func title(_ count: Int, locale: Locale) -> String {
        if count == 1 { return AppLocalization.string("1 unreviewed failed job", locale: locale) }
        return String(format: AppLocalization.string("%lld unreviewed failed jobs", locale: locale), locale: locale, Int64(count))
    }
}
