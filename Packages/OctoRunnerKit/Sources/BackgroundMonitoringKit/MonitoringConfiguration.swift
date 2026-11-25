import Foundation

public struct MonitoringConfiguration: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    public let revision: UUID
    public let runnerIDs: [UUID]

    public init(runnerIDs: [UUID]) {
        version = Self.currentVersion
        revision = UUID()
        self.runnerIDs = runnerIDs
    }
}
