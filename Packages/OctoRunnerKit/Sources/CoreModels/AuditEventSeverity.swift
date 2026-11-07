import Foundation

public enum AuditEventSeverity: String, CaseIterable, Codable, Sendable, Identifiable {
    case info = "info"
    case warning = "warning"
    case critical = "critical"

    public var id: String { rawValue }

    public var badgeTitle: String {
        switch self {
        case .info:
            return "INFO"
        case .warning:
            return "WARNING"
        case .critical:
            return "CRITICAL"
        }
    }
}
