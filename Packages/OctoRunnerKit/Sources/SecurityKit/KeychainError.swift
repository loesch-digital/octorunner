import Foundation
import Security

public enum KeychainError: Error, LocalizedError, CustomStringConvertible, Sendable, Equatable {
    case unexpectedStatus(OSStatus)
    case interactionNotAllowed
    case invalidDataEncoding

    public var description: String {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown OSStatus"
            return "KeychainError(\(status)): \(message)"
        case .interactionNotAllowed:
            return "KeychainError(\(errSecInteractionNotAllowed)): Device is locked; interaction not allowed."
        case .invalidDataEncoding:
            return "KeychainError: Secret data is not valid UTF-8."
        }
    }

    public var errorDescription: String? {
        description
    }
}
