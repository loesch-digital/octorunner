import Foundation

/// Conservative attribution: missing ancestors, changed parents or ambiguous roots omit a row.
enum RunnerProcessTree {
    static func associate(_ sample: RunnerProcessSample, targets: [RunnerProcessTarget], userID: UInt32) throws -> [(RunnerProcessMetadata, RunnerProcessTarget)] {
        let grouped = Dictionary(grouping: sample.processes, by: { $0.identity.pid })
        let processes = grouped.compactMapValues { rows -> RunnerProcessMetadata? in
            guard rows.count == 1, let process = rows.first, process.identity.pid > 1,
                  process.identity.startSeconds > 0, process.identity.startMicroseconds < 1_000_000,
                  process.userID == userID, process.executablePath.hasPrefix("/") else { return nil }
            return process
        }
        let roots = Dictionary(grouping: targets.filter { $0.rootPath.hasPrefix("/") }, by: { normalized($0.rootPath) })
        func owner(of process: RunnerProcessMetadata) -> RunnerProcessTarget? {
            var current = process
            var visited: Set<Int32> = []
            while visited.insert(current.identity.pid).inserted {
                if let root = runnerRoot(current.executablePath) {
                    let matches = roots[root] ?? []
                    return matches.count == 1 ? matches.first : nil
                }
                guard let parent = processes[current.parentPID], parent.identity.startedAt <= current.identity.startedAt else { return nil }
                current = parent
            }
            return nil
        }
        var result: [(RunnerProcessMetadata, RunnerProcessTarget)] = []
        for process in processes.values {
            try Task.checkCancellation()
            if let runner = owner(of: process) { result.append((process, runner)) }
        }
        return result.sorted { $0.0.identity.pid < $1.0.identity.pid }
    }

    private static func normalized(_ path: String) -> String {
        var result = URL(fileURLWithPath: path).standardizedFileURL.path(percentEncoded: false)
        while result.count > 1 && result.hasSuffix("/") { result.removeLast() }
        return result
    }

    private static func runnerRoot(_ path: String) -> String? {
        let executable = URL(fileURLWithPath: path)
        guard ["Runner.Listener", "Runner.Worker"].contains(executable.lastPathComponent) else { return nil }
        let bin = executable.deletingLastPathComponent()
        guard bin.lastPathComponent == "bin" || bin.lastPathComponent.wholeMatch(of: /bin\.[0-9]+\.[0-9]+\.[0-9]+/) != nil else { return nil }
        return normalized(bin.deletingLastPathComponent().path(percentEncoded: false))
    }
}
