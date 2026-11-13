import Foundation
import SwiftData

public enum AppAuditEvent: CaseIterable, Sendable {
    case started, stopped, updateStarted, updateFailed, updateInstalled

    @MainActor
    public func record(in context: ModelContext) throws {
        try Task.checkCancellation()
        let title: String
        let summary: String
        let category: AuditEventCategory
        let severity: AuditEventSeverity
        switch self {
        case .started:
            title = "App started"; summary = "OctoRunner GUI started."
            category = .system; severity = .info
        case .stopped:
            title = "App stopped"; summary = "OctoRunner GUI quit. Independently installed runner services may continue."
            category = .system; severity = .info
        case .updateStarted:
            title = "Update started"; summary = "Requested installation of a published OctoRunner update."
            category = .appUpdate; severity = .info
        case .updateFailed:
            title = "Update failed"; summary = "Automatic installation did not complete. The published release page was offered as a fallback."
            category = .appUpdate; severity = .warning
        case .updateInstalled:
            title = "Update installed"; summary = "The installer completed; OctoRunner will quit to finish the update."
            category = .appUpdate; severity = .info
        }
        context.insert(AuditLogEntity(category: category, severity: severity, title: title, summary: summary))
        try context.save()
    }
}
