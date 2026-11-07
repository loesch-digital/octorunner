import Foundation
import SwiftData

@MainActor
public enum AuditLogRecorder {
    @discardableResult
    public static func record(
        in modelContext: ModelContext,
        category: AuditEventCategory,
        severity: AuditEventSeverity = .info,
        title: String,
        summary: String,
        actorAccountLogin: String? = nil,
        targetRunnerName: String? = nil,
        previousValue: String? = nil,
        newValue: String? = nil
    ) -> AuditLogEntity {
        let entry = AuditLogEntity(
            category: category,
            severity: severity,
            title: title,
            summary: summary,
            actorAccountLogin: actorAccountLogin,
            targetRunnerName: targetRunnerName,
            previousValue: previousValue,
            newValue: newValue
        )
        modelContext.insert(entry)
        try? modelContext.save()
        return entry
    }
}
