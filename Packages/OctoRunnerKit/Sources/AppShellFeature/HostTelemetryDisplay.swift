import Foundation
import TelemetryKit

public struct HostTelemetryDisplay: Sendable, Equatable {
    public let cpuBrand: String
    public let coreCount: String
    public let memoryCapacity: String
    public let memoryUsed: String

    public init(snapshot: HostTelemetrySnapshot?, locale: Locale) {
        cpuBrand = snapshot?.cpuSummary ?? "—"
        coreCount = snapshot.map { $0.totalCoreCount.formatted(.number.locale(locale)) } ?? "—"
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1)).locale(locale)
        memoryCapacity = snapshot.map { $0.physicalMemoryGB.formatted(format) } ?? "—"
        memoryUsed = snapshot?.usedMemoryGB.map { $0.formatted(format) } ?? "—"
    }
}
