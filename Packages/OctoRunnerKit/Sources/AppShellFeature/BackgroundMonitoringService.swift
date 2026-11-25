import BackgroundMonitoringKit
import Foundation
import ServiceManagement

public enum BackgroundMonitoringState: Sendable {
    case disabled, enabled, requiresApproval, unavailable
}

public protocol BackgroundMonitoringServicing: Sendable {
    func status() async -> BackgroundMonitoringState
    func setEnabled(_ enabled: Bool) async throws
    func startMonitoring(revision: UUID) async throws
}

public actor BackgroundMonitoringService: BackgroundMonitoringServicing {
    private let service = SMAppService.agent(plistName: "io.octorunner.macos.background.plist")
    private let dockPreference = "preferences.monitorLocalRunnersAfterQuitting"
    private let store = MonitoringSnapshotStore(directory: MonitoringStorage.directory)

    public init() {}

    public func status() -> BackgroundMonitoringState {
        if #available(macOS 27.0, *) {
            guard let executable, FileManager.default.isExecutableFile(atPath: executable.path) else {
                return .unavailable
            }
            return UserDefaults.standard.bool(forKey: dockPreference) ? .enabled : .disabled
        }
        return switch service.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) async throws {
        if #available(macOS 27.0, *) {
            try await unregisterLaunchAgentIfNeeded()
            if !enabled { try await waitForWorkerExit() }
            UserDefaults.standard.set(enabled, forKey: dockPreference)
            return
        }
        switch (enabled, status()) {
        case (true, .disabled), (true, .unavailable):
            try service.register()
        case (false, .enabled), (false, .requiresApproval):
            try await service.unregister()
        default:
            break
        }
    }

    public func startMonitoring(revision: UUID) async throws {
        guard #available(macOS 27.0, *) else { return }
        try await unregisterLaunchAgentIfNeeded()
        try await waitForWorkerExit()
        guard let executable, let configuration = try store.readConfiguration(),
              configuration.revision == revision else { throw CocoaError(.executableLoad) }
        let worker = Process()
        worker.executableURL = executable
        worker.arguments = ["--configuration-revision", revision.uuidString]
        worker.standardOutput = FileHandle.nullDevice
        worker.standardError = FileHandle.nullDevice
        try worker.run()
        do {
            for _ in 0..<30 {
                guard worker.isRunning else { break }
                if try store.readObservation(for: configuration, at: Date()) != nil { return }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw CocoaError(.executableLoad)
        } catch {
            if worker.isRunning { worker.terminate() }
            throw error
        }
    }

    private var executable: URL? {
        Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "OctoRunnerBackgroundMonitor")
    }

    private func unregisterLaunchAgentIfNeeded() async throws {
        if service.status == .enabled || service.status == .requiresApproval {
            try await service.unregister()
        }
    }

    private func waitForWorkerExit() async throws {
        let directory = MonitoringStorage.directory
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let lifetime = MonitoringLease(lockFile: directory.appending(path: "worker.lock"))
        for _ in 0..<30 {
            if try await lifetime.withOwnership({ true }) == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CocoaError(.executableLoad)
    }
}
