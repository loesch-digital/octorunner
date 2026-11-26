import Foundation

public struct RunnerResourceUsage: Equatable, Sendable {
    public let cpuPercent: Double?
    public let residentBytes: UInt64?

    public init(cpuPercent: Double?, residentBytes: UInt64?) {
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
    }

    public static func byRunner(_ processes: [InspectedRunnerProcess]) -> [UUID: Self] {
        Dictionary(grouping: processes, by: \.runner.id).mapValues { group in
            let cpu = group.compactMap(\.cpuPercent)
            let bytes = group.compactMap(\.metadata.residentBytes)
            return Self(
                cpuPercent: cpu.isEmpty ? nil : cpu.reduce(0, +),
                residentBytes: bytes.isEmpty ? nil : bytes.reduce(0) { total, value in
                    let (sum, overflow) = total.addingReportingOverflow(value)
                    return overflow ? .max : sum
                }
            )
        }
    }
}
