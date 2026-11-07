import Foundation

public enum AuditEventCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case authentication = "authentication"
    case runnerLifecycle = "runner_lifecycle"
    case configuration = "configuration"
    case appUpdate = "app_update"
    case system = "system"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .authentication:
            return "Authentication"
        case .runnerLifecycle:
            return "Runner Lifecycle"
        case .configuration:
            return "Configuration"
        case .appUpdate:
            return "App Update"
        case .system:
            return "System"
        }
    }

    public var systemImage: String {
        switch self {
        case .authentication:
            return "person.badge.key.fill"
        case .runnerLifecycle:
            return "terminal.fill"
        case .configuration:
            return "slider.horizontal.3"
        case .appUpdate:
            return "arrow.down.app.fill"
        case .system:
            return "cpu.fill"
        }
    }
}
