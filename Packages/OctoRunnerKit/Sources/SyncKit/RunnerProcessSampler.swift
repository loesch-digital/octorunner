import Foundation

/// Reads process metadata only; never opens a runner directory or log file.
public actor RunnerProcessSampler: RunnerProcessSampling {
    public init() {}

    public func sample() throws -> [String: RunnerProcessPresence] {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        // comm contains the executable path without arguments. Keep spaces in it.
        process.arguments = ["-axo", "pid=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        return try Self.parseExecutableTable(String(decoding: data, as: UTF8.self))
    }

    public nonisolated static func parseExecutableTable(_ output: String) throws -> [String: RunnerProcessPresence] {
        let lines = output.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        var result: [String: RunnerProcessPresence] = [:]
        for line in lines {
            let parts = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2, let pid = Int32(parts[0]), pid > 0 else { throw CocoaError(.fileReadCorruptFile) }
            let executable = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let listener = executable.hasSuffix("/bin/Runner.Listener")
            let worker = executable.hasSuffix("/bin/Runner.Worker")
            guard executable.hasPrefix("/"), listener || worker else { continue }
            let rootURL = URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent()
            let root = LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: rootURL)
            var presence = result[root] ?? RunnerProcessPresence()
            if listener { presence.listenerPID = pid }
            if worker { presence.workerPID = pid }
            result[root] = presence
        }
        return result
    }
}
