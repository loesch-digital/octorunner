import Foundation

public struct VolumeCapacitySnapshot: Sendable, Equatable {
    public let availableBytes: Int64
    public let totalBytes: Int64
    public let observedAt: Date

    public init?(availableBytes: Int64, totalBytes: Int64, observedAt: Date = .now) {
        guard totalBytes > 0, availableBytes >= 0, availableBytes <= totalBytes else { return nil }
        self.availableBytes = availableBytes
        self.totalBytes = totalBytes
        self.observedAt = observedAt
    }

    public func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(observedAt)
        return age >= -5 && age <= 60
    }
}
