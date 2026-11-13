public struct HostMemorySnapshot: Sendable, Equatable {
    public let appBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let usedBytes: UInt64

    init?(statistics: HostVMStatistics, physicalMemoryBytes: UInt64) {
        guard statistics.pageSize > 0, statistics.purgeablePages <= statistics.anonymousPages else { return nil }
        // Anonymous resident pages exclude file-backed caches. Purgeable pages
        // are reclaimable; compressedPages counts physical compressor storage,
        // not the uncompressed size of its contents.
        let app = (statistics.anonymousPages - statistics.purgeablePages).multipliedReportingOverflow(by: statistics.pageSize)
        let wired = statistics.wiredPages.multipliedReportingOverflow(by: statistics.pageSize)
        let compressed = statistics.compressedPages.multipliedReportingOverflow(by: statistics.pageSize)
        guard !app.overflow, !wired.overflow, !compressed.overflow else { return nil }
        let subtotal = app.partialValue.addingReportingOverflow(wired.partialValue)
        let total = subtotal.partialValue.addingReportingOverflow(compressed.partialValue)
        guard !subtotal.overflow, !total.overflow, total.partialValue <= physicalMemoryBytes else { return nil }
        appBytes = app.partialValue
        wiredBytes = wired.partialValue
        compressedBytes = compressed.partialValue
        usedBytes = total.partialValue
    }
}
