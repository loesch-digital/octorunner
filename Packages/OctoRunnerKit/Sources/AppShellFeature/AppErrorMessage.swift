import Foundation
import GitHubAPI
import RunnerEngine

public enum AppErrorMessage {
    case key(String.LocalizationValue)
    case failure(any Error)

    func localized(locale: Locale) -> String {
        switch self {
        case .key(let key):
            return AppLocalization.string(key, locale: locale)
        case .failure(let error):
            let key: String.LocalizationValue
            switch error {
            case let error as GitHubAuthError:
                switch error {
                case .invalidHTTPStatus(let code): key = "GitHub returned HTTP status \(code)."
                case .expiredDeviceCode: key = "The device authorization code has expired. Please request a new code."
                case .accessDenied: key = "Authorization was cancelled or denied in the browser."
                case .invalidTokenOrUnauthorized: key = "The provided GitHub token is invalid or expired."
                case .missingRequiredScopes(let scopes): key = "Missing required token scopes: \(scopes.joined(separator: ", "))."
                case .unexpectedResponse(let detail): key = "Unexpected response from GitHub: \(detail)"
                }
            case let error as RunnerEngineError:
                switch error {
                case .sha256Mismatch(let expected, let actual): key = "Runner binary SHA256 checksum mismatch (expected \(expected), got \(actual))."
                case .downloadFailed(let detail): key = "Failed to download runner binary: \(detail)"
                case .extractionFailed(let code): key = "Failed to extract runner archive (exit code \(Int(code)))."
                case .configurationFailed(let code, let log): key = "config.sh exited with code \(Int(code)): \(log)"
                case .launchAgentRegistrationFailed(let code, let log): key = "launchctl exited with code \(Int(code)): \(log)"
                case .invalidRunnerName: key = "Runner names must be a single non-empty directory name without path separators or control characters."
                case .runnerDirectoryAlreadyExists: key = "A managed runner directory already exists. Choose another name to preserve the existing runner."
                }
            default:
                return error.localizedDescription
            }
            return AppLocalization.string(key, locale: locale)
        }
    }
}
