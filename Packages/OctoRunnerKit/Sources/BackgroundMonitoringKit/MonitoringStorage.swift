import Foundation

public enum MonitoringStorage {
    public static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "io.octorunner.macos", directoryHint: .isDirectory)
            .appending(path: "background-monitoring", directoryHint: .isDirectory)
    }
}
