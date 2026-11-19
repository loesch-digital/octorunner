import Foundation

public struct WorkflowHistoryRepositoryFailure: Sendable, Equatable {
    public let repository: String
    public let error: WorkflowHistoryLoadError

    public func localizedMessage(locale: Locale) -> String {
        let key: String.LocalizationValue
        switch error {
        case .authenticationRequired: key = "Reconnect this GitHub account to load history"
        case .permissionDenied: key = "This token cannot read Actions for the selected repository"
        case .rateLimited: key = "GitHub rate limit reached; refresh is paused"
        case .tooManyPages: key = "Job details exceeded the safe pagination limit"
        case .unavailable: key = "History could not be loaded; saved observations remain available"
        }
        return repository + ": " + AppLocalization.string(key, locale: locale)
    }
}
