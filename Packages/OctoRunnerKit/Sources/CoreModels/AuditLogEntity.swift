import Foundation
import SwiftData

/// Persists configuration changes, runner lifecycle events, and system telemetry events.
/// Follows `swiftdata-pro` rules:
/// - Does NOT use the reserved property name `description` (uses `summary` instead).
/// - Omits `#Index` on this write-heavy logging table (`swiftdata-pro/references/indexing.md`).
/// - Provides property-level default values on all attributes for seamless lightweight migration.
@Model
public final class AuditLogEntity {
    public var id: UUID = UUID()
    public var timestamp: Date = Date.now
    public var categoryRaw: String = AuditEventCategory.system.rawValue
    public var severityRaw: String = AuditEventSeverity.info.rawValue
    public var title: String = ""
    public var summary: String = ""
    public var actorAccountLogin: String?
    public var targetRunnerName: String?
    public var previousValue: String?
    public var newValue: String?

    public var category: AuditEventCategory {
        get { AuditEventCategory(rawValue: categoryRaw) ?? .system }
        set { categoryRaw = newValue.rawValue }
    }

    public var severity: AuditEventSeverity {
        get { AuditEventSeverity(rawValue: severityRaw) ?? .info }
        set { severityRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        category: AuditEventCategory = .system,
        severity: AuditEventSeverity = .info,
        title: String,
        summary: String,
        actorAccountLogin: String? = nil,
        targetRunnerName: String? = nil,
        previousValue: String? = nil,
        newValue: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.categoryRaw = category.rawValue
        self.severityRaw = severity.rawValue
        self.title = title
        self.summary = summary
        self.actorAccountLogin = actorAccountLogin
        self.targetRunnerName = targetRunnerName
        self.previousValue = previousValue
        self.newValue = newValue
    }
}
