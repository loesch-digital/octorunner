import Foundation

public enum LaunchAgentPlistGenerator {
    public static func generatePlistData(
        serviceLabel: String,
        runnerRootDirectory: URL,
        configuration: RunnerLaunchConfiguration = RunnerLaunchConfiguration()
    ) throws -> Data {
        let rootPath = runnerRootDirectory.path(percentEncoded: false)
        let runScriptPath = runnerRootDirectory.appending(path: "run.sh").path(percentEncoded: false)
        let diagDir = runnerRootDirectory.appending(path: "_diag")

        let keepAlive: Any
        switch configuration.runtimePolicy.restartPolicy {
        case .always: keepAlive = true
        case .onNonZeroExit: keepAlive = ["SuccessfulExit": false]
        case .manual: keepAlive = false
        }
        let plistDict: [String: Any] = [
            "Label": serviceLabel,
            "ProgramArguments": ["/bin/bash", runScriptPath],
            "WorkingDirectory": rootPath,
            "RunAtLoad": true,
            "KeepAlive": keepAlive,
            "ThrottleInterval": configuration.runtimePolicy.restartDelaySeconds,
            "EnvironmentVariables": configuration.environment,
            "StandardOutPath": diagDir.appending(path: "launchd.stdout.log").path(percentEncoded: false),
            "StandardErrorPath": diagDir.appending(path: "launchd.stderr.log").path(percentEncoded: false)
        ]

        return try PropertyListSerialization.data(
            fromPropertyList: plistDict,
            format: .xml,
            options: 0
        )
    }

    public static func launchAgentPlistURL(for serviceLabel: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appending(path: "Library/LaunchAgents/\(serviceLabel).plist")
    }
}
