import CoreModels
import Foundation
import ServiceManagement

public actor RunnerSupervisorActor: LoginItemServicing, RunnerServiceStateReading {
    public init() {}

    public func isUnloaded(label: String) throws -> Bool {
        try Task.checkCancellation()
        guard label.hasPrefix("io.octorunner.agent."), !label.contains("/"), !label.contains("\\"),
              label.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw CocoaError(.fileReadNoPermission) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationReason == .exit else { throw CocoaError(.fileReadUnknown) }
        switch process.terminationStatus {
        case 0: return false
        case 113: return true // Verified locally against an absent synthetic label.
        default: throw CocoaError(.fileReadUnknown)
        }
    }

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
