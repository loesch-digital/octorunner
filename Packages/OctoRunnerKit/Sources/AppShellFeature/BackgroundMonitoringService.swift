import ServiceManagement

public enum BackgroundMonitoringState: Sendable {
    case disabled, enabled, requiresApproval, unavailable
}

public protocol BackgroundMonitoringServicing: Sendable {
    func status() async -> BackgroundMonitoringState
    func setEnabled(_ enabled: Bool) async throws
}

public actor BackgroundMonitoringService: BackgroundMonitoringServicing {
    private let service = SMAppService.agent(plistName: "io.octorunner.macos.background.plist")

    public init() {}

    public func status() -> BackgroundMonitoringState {
        switch service.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) async throws {
        switch (enabled, status()) {
        case (true, .disabled), (true, .unavailable):
            try service.register()
        case (false, .enabled), (false, .requiresApproval):
            try await service.unregister()
        default:
            break
        }
    }
}
