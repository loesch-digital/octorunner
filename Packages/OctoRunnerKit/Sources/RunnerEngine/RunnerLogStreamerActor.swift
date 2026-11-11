import CoreModels
import Foundation

public actor RunnerLogStreamerActor {
    public init() {}

    /// Reads the most recent diagnostic log lines from `<runnerRoot>/_diag/Runner_*.log` or `Worker_*.log`.
    public func readRecentLogLines(
        forRunnerRoot runnerRoot: URL,
        maxLines: Int = 80
    ) -> [RunnerLogLine] {
        let diagDir = runnerRoot.appending(path: "_diag", directoryHint: .isDirectory)
        // Do not enumerate or prefetch metadata through links to unrelated folders.
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: diagDir.path())) == nil else { return [] }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diagDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let logFiles = files
            .filter {
                $0.pathExtension == "log"
                    && (try? FileManager.default.destinationOfSymbolicLink(atPath: $0.path())) == nil
            }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }

        guard let latestFile = logFiles.first,
              let content = try? String(contentsOf: latestFile, encoding: .utf8)
        else {
            return []
        }

        let rawLines = content
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let tailSlice = rawLines.suffix(maxLines)
        return tailSlice.enumerated().map { idx, line in
            RunnerLogLine.parse(line, index: idx + 1)
        }
    }
}
