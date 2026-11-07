import Foundation

public enum LaunchAgentPlistGenerator {
    public static func generatePlistData(
        serviceLabel: String,
        runnerRootDirectory: URL
    ) throws -> Data {
        let rootPath = runnerRootDirectory.path()
        let runScriptPath = runnerRootDirectory.appending(path: "run.sh").path()
        let diagDir = runnerRootDirectory.appending(path: "_diag")

        let plistDict: [String: Any] = [
            "Label": serviceLabel,
            "ProgramArguments": ["/bin/bash", runScriptPath],
            "WorkingDirectory": rootPath,
            "RunAtLoad": true,
            "KeepAlive": true,
            "EnvironmentVariables": [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "LANG": "en_US.UTF-8"
            ],
            "StandardOutPath": diagDir.appending(path: "launchd.stdout.log").path(),
            "StandardErrorPath": diagDir.appending(path: "launchd.stderr.log").path()
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
