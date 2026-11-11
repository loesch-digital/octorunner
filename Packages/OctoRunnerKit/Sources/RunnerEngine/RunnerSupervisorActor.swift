import CoreModels
import Foundation
import ServiceManagement

public actor RunnerSupervisorActor: LoginItemServicing {
    public init() {}

    public func status() -> LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .disabled
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) async throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try await SMAppService.mainApp.unregister()
        }
    }

    public func isLoginAutostartEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setLoginAutostart(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
