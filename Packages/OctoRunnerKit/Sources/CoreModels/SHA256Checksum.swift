import Foundation

/// Validated hexadecimal metadata; never treats an absent digest as verification.
public struct SHA256Checksum: Sendable, Equatable {
    public let hex: String

    public init?(_ raw: String) {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.utf8.count == 64,
              normalized.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        hex = normalized
    }
}
