public struct HostVMStatistics: Sendable, Equatable {
    public let pageSize: UInt64
    public let anonymousPages: UInt64
    public let wiredPages: UInt64
    public let compressedPages: UInt64
    public let purgeablePages: UInt64

    public init(pageSize: UInt64, anonymousPages: UInt64, wiredPages: UInt64, compressedPages: UInt64, purgeablePages: UInt64) {
        self.pageSize = pageSize
        self.anonymousPages = anonymousPages
        self.wiredPages = wiredPages
        self.compressedPages = compressedPages
        self.purgeablePages = purgeablePages
    }
}
