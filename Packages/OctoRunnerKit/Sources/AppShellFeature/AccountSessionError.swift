import Foundation

public enum AccountSessionError: Error, Equatable, Sendable {
    case accountNotFound
    case accountChanged
    case credentialDeletionFailed
    case metadataPersistenceFailed

    public func localizedMessage(locale: Locale) -> String {
        let key: String.LocalizationValue
        switch self {
        case .accountNotFound: key = "This account is no longer connected."
        case .accountChanged: key = "This account changed during sign-out. Review it and try again."
        case .credentialDeletionFailed: key = "The Keychain credential could not be removed. The account is still connected; please try again."
        case .metadataPersistenceFailed: key = "Account changes could not be saved. Please try again."
        }
        return AppLocalization.string(key, locale: locale)
    }
}
