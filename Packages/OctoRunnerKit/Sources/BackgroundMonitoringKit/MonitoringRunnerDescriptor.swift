import Foundation

public struct MonitoringRunnerDescriptor: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let processRootPath: String?

    public init(id: UUID, name: String, processRootPath: String?) {
        self.id = id
        self.name = name
        self.processRootPath = processRootPath
    }
}
