import Foundation

public enum GitHubRunnerChecksumError: LocalizedError, Sendable, Equatable {
    case invalidMetadata
    case unavailable
    case checksumUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidMetadata: "Runner download metadata does not identify a supported official macOS ARM64 archive."
        case .unavailable: "The official runner release could not be checked. Try again later; no unverified archive was accepted."
        case .checksumUnavailable: "The official runner release does not provide an unambiguous SHA-256 checksum for this archive."
        }
    }
}
