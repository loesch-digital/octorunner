import Foundation

/// Automatic startup work must not cause protected-folder consent prompts.
/// NSOpenPanel selections and explicit console actions are handled separately.
public enum RunnerDirectoryAccessPolicy {
    public static func allowsAutomaticRead(
        at url: URL,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> Bool {
        let candidate = url.standardizedFileURL
        let path = LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: candidate)
        let isWithinAutomaticRoots = ["actions-runner", ".octorunner/runners", "Library/Application Support/io.octorunner.macos/runners"].contains { relativePath in
            let root = LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: homeDirectory.appending(path: relativePath))
            return path == root || path.hasPrefix(root + "/")
        }
        // Reject external paths without querying their filesystem metadata.
        guard isWithinAutomaticRoots else { return false }
        return candidate == candidate.resolvingSymlinksInPath()
    }
}
