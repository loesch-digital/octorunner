import Foundation

public protocol RunnerServiceStateReading: Sendable {
    func isUnloaded(label: String) async throws -> Bool
}

public struct LaunchAgentServiceStateReader: RunnerServiceStateReading {
    public init() {}

    public func isUnloaded(label: String) async throws -> Bool {
        try Task.checkCancellation()
        guard label.hasPrefix("io.octorunner.agent."), !label.contains("/"), !label.contains("\\"),
              label.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw CocoaError(.fileReadNoPermission)
        }
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        switch try await ConfigurationProcessRunner.run(process) {
        case 0: return false
        case 113: return true
        default: throw CocoaError(.fileReadUnknown)
        }
    }
}
