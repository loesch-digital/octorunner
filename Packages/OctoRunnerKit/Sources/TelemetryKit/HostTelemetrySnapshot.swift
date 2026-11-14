public struct HostTelemetrySnapshot: Sendable, Equatable {
    public let cpuSummary: String
    public let totalCoreCount: Int
    public let physicalMemoryGB: Double
    public let usedMemoryGB: Double?
    public let osVersionString: String
    public let cpuUsagePercent: Double?
    public let memory: HostMemorySnapshot?
    public let performanceCoreCount: Int?
    public let efficiencyCoreCount: Int?
    public let coreClusters: [HostCPUCluster]
    public let memoryPressure: HostMemoryPressure?
    public let thermalState: HostThermalState?

    public init(cpuSummary: String, totalCoreCount: Int, physicalMemoryGB: Double, usedMemoryGB: Double?, osVersionString: String,
                cpuUsagePercent: Double? = nil, memory: HostMemorySnapshot? = nil, performanceCoreCount: Int? = nil, efficiencyCoreCount: Int? = nil, coreClusters: [HostCPUCluster] = [], memoryPressure: HostMemoryPressure? = nil, thermalState: HostThermalState? = nil) {
        self.cpuSummary = cpuSummary
        self.totalCoreCount = totalCoreCount
        self.physicalMemoryGB = physicalMemoryGB
        self.usedMemoryGB = usedMemoryGB
        self.osVersionString = osVersionString
        self.cpuUsagePercent = cpuUsagePercent
        self.memory = memory
        self.performanceCoreCount = performanceCoreCount
        self.efficiencyCoreCount = efficiencyCoreCount
        self.coreClusters = coreClusters
        self.memoryPressure = memoryPressure
        self.thermalState = thermalState
    }
}
