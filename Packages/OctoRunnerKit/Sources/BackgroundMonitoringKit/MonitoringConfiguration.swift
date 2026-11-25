import Foundation

public struct MonitoringConfiguration: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    public let revision: UUID
    public let runners: [MonitoringRunnerDescriptor]

    public init(runners: [MonitoringRunnerDescriptor]) {
        version = Self.currentVersion
        revision = UUID()
        self.runners = runners
    }
}
