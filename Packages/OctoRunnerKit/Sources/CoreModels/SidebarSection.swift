import Foundation

public enum SidebarSection: String, CaseIterable, Sendable, Identifiable {
    case allRunners = "all_runners"
    case activeDaemons = "active_daemons"
    case failedFaulted = "failed_faulted"
    case queueWorkpools = "queue_workpools"
    case hostTelemetry = "host_telemetry"
    case launchdSettings = "launchd_settings"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .allRunners:
            return "All Runners"
        case .activeDaemons:
            return "Active Daemons"
        case .failedFaulted:
            return "Failed / Faulted"
        case .queueWorkpools:
            return "Queue & Workpools"
        case .launchdSettings:
            return "Settings"
        case .hostTelemetry:
            return "Host Telemetry"
        }
    }

    public var systemImage: String {
        switch self {
        case .allRunners:
            return "server.rack"
        case .activeDaemons:
            return "play.circle.fill"
        case .failedFaulted:
            return "exclamationmark.triangle.fill"
        case .queueWorkpools:
            return "list.bullet.rectangle"
        case .launchdSettings:
            return "gearshape"
        case .hostTelemetry:
            return "waveform.path.ecg"
        }
    }
}
