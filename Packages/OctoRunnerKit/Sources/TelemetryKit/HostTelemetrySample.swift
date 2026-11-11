public struct HostTelemetrySample: Sendable, Equatable {
    public let cpuSummary: String
    public let totalCoreCount: Int
    public let physicalMemoryBytes: UInt64
    public let osVersionString: String
    public let cpuTicks: HostCPUTicks?
    public let vmStatistics: HostVMStatistics?
    public let performanceCoreCount: Int?
    public let efficiencyCoreCount: Int?
    public let coreClusters: [HostCPUCluster]

    public init(cpuSummary: String, totalCoreCount: Int, physicalMemoryBytes: UInt64, osVersionString: String, cpuTicks: HostCPUTicks?, vmStatistics: HostVMStatistics?, performanceCoreCount: Int? = nil, efficiencyCoreCount: Int? = nil, coreClusters: [HostCPUCluster] = []) {
        self.cpuSummary = cpuSummary
        self.totalCoreCount = totalCoreCount
        self.physicalMemoryBytes = physicalMemoryBytes
        self.osVersionString = osVersionString
        self.cpuTicks = cpuTicks
        self.vmStatistics = vmStatistics
        self.performanceCoreCount = performanceCoreCount
        self.efficiencyCoreCount = efficiencyCoreCount
        self.coreClusters = coreClusters
    }
}
