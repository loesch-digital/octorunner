import Foundation

public struct RunnerProcessTarget: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let rootPath: String

    public init(id: UUID, name: String, rootPath: String) {
        self.id = id; self.name = name; self.rootPath = rootPath
    }
}
