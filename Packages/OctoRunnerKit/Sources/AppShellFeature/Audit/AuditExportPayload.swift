import Foundation

struct AuditExportPayload: Codable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let events: [AuditEventSnapshot]
}
