import CoreModels
import Foundation
import ServiceManagement

public actor RunnerSupervisorActor {
    public init() {}

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
