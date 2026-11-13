import Foundation

public struct ManagedStorageRunner: Sendable, Equatable {
    public let id: UUID
    public let root: URL
    public let serviceLabel: String

    public init(id: UUID, root: URL, serviceLabel: String) {
        self.id = id; self.root = root; self.serviceLabel = serviceLabel
    }
}
