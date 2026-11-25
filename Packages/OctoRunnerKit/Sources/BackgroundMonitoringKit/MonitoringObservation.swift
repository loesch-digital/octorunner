import CoreModels
import Foundation

public struct MonitoringObservation: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    public let configurationRevision: UUID
    public let observedAt: Date
    /// Missing runner IDs represent unknown status.
    public let statuses: [UUID: RunnerStatus]

    public init(configurationRevision: UUID, observedAt: Date, statuses: [UUID: RunnerStatus]) {
        version = Self.currentVersion
        self.configurationRevision = configurationRevision
        self.observedAt = observedAt
        self.statuses = statuses
    }
}
