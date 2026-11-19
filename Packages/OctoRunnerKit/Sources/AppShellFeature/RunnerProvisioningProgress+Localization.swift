import Foundation
import RunnerEngine

extension RunnerProvisioningProgress {
    public func localizedMessage(locale: Locale) -> String {
        switch self {
        case .fetchingMetadata:
            AppLocalization.string("Fetching macOS ARM64 runner binary metadata from GitHub…", locale: locale)
        case .verifyingBinary(let filename):
            AppLocalization.string("Ensuring verified runner binary (\(filename)) in cache…", locale: locale)
        case .registeringInstances(let count):
            AppLocalization.string("Provisioning runner instances: \(count)…", locale: locale)
        }
    }
}
