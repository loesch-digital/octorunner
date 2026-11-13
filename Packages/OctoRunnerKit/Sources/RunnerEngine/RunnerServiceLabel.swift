import Foundation

public enum RunnerServiceLabel {
    public static func forRunner(named name: String) -> String {
        "io.octorunner.agent.\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"
    }
}
