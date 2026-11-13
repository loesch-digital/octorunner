import CoreModels
import Foundation

/// A value snapshot for one provisioning operation. Never contains credentials.
public struct RunnerLaunchConfiguration: Sendable, Equatable {
    public let runtimePolicy: RunnerRuntimePolicy
    public let inheritHostPath: Bool
    public let hostPath: String

    public init(
        runtimePolicy: RunnerRuntimePolicy = RunnerRuntimePolicy(),
        inheritHostPath: Bool = true,
        hostPath: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) {
        self.runtimePolicy = runtimePolicy.validated()
        self.inheritHostPath = inheritHostPath
        self.hostPath = hostPath
    }

    public var environment: [String: String] {
        let system = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var paths: [String] = []
        if inheritHostPath {
            // Empty or relative PATH components would search a job's working directory.
            paths = hostPath.prefix(32_768).split(separator: ":").prefix(64).map(String.init).filter {
                $0.hasPrefix("/") && !$0.contains(where: { $0.isNewline || $0 == "\0" })
            }
            paths += ["/opt/homebrew/bin", "/usr/local/bin"]
        }
        paths += system
        var seen: Set<String> = []
        let path = paths.filter { seen.insert($0).inserted }.joined(separator: ":")
        return ["PATH": path, "SHELL": runtimePolicy.shell.rawValue, "LANG": "en_US.UTF-8"]
    }
}
