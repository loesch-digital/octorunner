import Foundation

public struct WorkflowJobLogSnapshot: Sendable, Equatable {
    public let text: String
    public let observedAt: Date
    public let isTruncated: Bool

    public init(text: String, observedAt: Date, isTruncated: Bool) {
        self.text = text; self.observedAt = observedAt; self.isTruncated = isTruncated
    }
}
