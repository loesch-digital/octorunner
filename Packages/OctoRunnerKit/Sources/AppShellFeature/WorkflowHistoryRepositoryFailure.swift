import Foundation

public struct WorkflowHistoryRepositoryFailure: Sendable, Equatable {
    public let repository: String
    public let error: WorkflowHistoryLoadError

    public func localizedMessage(locale: Locale) -> String {
        repository + ": " + Self.localizedReason(error, locale: locale)
    }

    static func banner(error: WorkflowHistoryLoadError?, failures: [Self], locale: Locale) -> String? {
        var lines: [String] = []
        if let error {
            lines.append(localizedReason(error, locale: locale))
        }
        if !failures.isEmpty {
            lines.append(AppLocalization.string("Some repositories could not be refreshed", locale: locale) + ":")
            lines.append(contentsOf: failures.map { $0.localizedMessage(locale: locale) })
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func localizedReason(_ error: WorkflowHistoryLoadError, locale: Locale) -> String {
        let key: String.LocalizationValue
        switch error {
        case .authenticationRequired: key = "Reconnect this GitHub account to load history"
        case .permissionDenied: key = "This token cannot read Actions for the selected repository"
        case .resourceNotFound: key = "GitHub could not find this Actions resource or it is not visible to this account (HTTP 404)."
        case .rateLimited: key = "GitHub rate limit reached; refresh is paused"
        case .tooManyPages: key = "Job details exceeded the safe pagination limit"
        case .unavailable: key = "History could not be loaded; saved observations remain available"
        }
        return AppLocalization.string(key, locale: locale)
    }
}
