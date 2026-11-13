import CoreModels
import Foundation

struct AuditEventSnapshot: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: String
    let severity: String
    let title: String
    let summary: String
    let actorAccountLogin: String?
    let targetRunnerName: String?
    let previousValue: String?
    let newValue: String?

    @MainActor init(_ event: AuditLogEntity) {
        id = event.id; timestamp = event.timestamp
        category = event.categoryRaw; severity = event.severityRaw
        title = event.title; summary = event.summary
        actorAccountLogin = event.actorAccountLogin; targetRunnerName = event.targetRunnerName
        previousValue = event.previousValue; newValue = event.newValue
    }
}
