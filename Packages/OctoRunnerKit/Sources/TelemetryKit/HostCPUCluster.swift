public struct HostCPUCluster: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let physicalCoreCount: Int

    public init(id: Int, name: String, physicalCoreCount: Int) {
        self.id = id
        self.name = name
        self.physicalCoreCount = physicalCoreCount
    }
}
