import CoreModels
import Foundation

public actor LocalRunnerDiscoveryActor {
    private let homeDirectory: URL
    private let processTableProvider: (@Sendable () -> [String: LocalRunnerProcessState])?

    public init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        processTableProvider: (@Sendable () -> [String: LocalRunnerProcessState])? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.processTableProvider = processTableProvider
    }

    public static func normalizedDirectoryPath(for url: URL) -> String {
        let raw = url.standardizedFileURL.path(percentEncoded: false)
        guard raw.count > 1, raw.hasSuffix("/") else { return raw }
        return String(raw.dropLast())
    }

    /// Parses output of `/bin/ps -axo pid=,command=` to locate active `Runner.Listener` and `Runner.Worker` processes.
    /// Keyed by standardized runner root directory path (without trailing slash).
    public static func parseProcessTable(_ psOutput: String) -> [String: LocalRunnerProcessState] {
        var states: [String: LocalRunnerProcessState] = [:]

        for rawLine in psOutput.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2,
                  let pid = Int32(parts[0])
            else { continue }

            let commandLine = String(parts[1])
            guard commandLine.contains("Runner.Listener") || commandLine.contains("Runner.Worker") else {
                continue
            }

            // Extract executable path (first token of commandLine)
            let executablePath = String(commandLine.split(whereSeparator: \.isWhitespace).first ?? "")
            guard executablePath.hasPrefix("/") else { continue }

            let execURL = URL(fileURLWithPath: executablePath)
            let binDir = execURL.deletingLastPathComponent()
            let runnerRootURL = binDir.deletingLastPathComponent()
            let rootPath = Self.normalizedDirectoryPath(for: runnerRootURL)

            if commandLine.contains("Runner.Listener") {
                let existingWorker = states[rootPath]?.isWorkerActive ?? false
                states[rootPath] = LocalRunnerProcessState(listenerPID: pid, isWorkerActive: existingWorker)
            } else if commandLine.contains("Runner.Worker") {
                if var existing = states[rootPath] {
                    existing.isWorkerActive = true
                    states[rootPath] = existing
                } else {
                    states[rootPath] = LocalRunnerProcessState(listenerPID: pid, isWorkerActive: true)
                }
            }
        }

        return states
    }

    public func queryLiveProcessTable() -> [String: LocalRunnerProcessState] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            return Self.parseProcessTable(output)
        } catch {
            return [:]
        }
    }

    public func inspectRunnerDirectory(
        at directoryURL: URL,
        activeProcesses: [String: LocalRunnerProcessState]
    ) -> DiscoveredLocalRunner? {
        let standardizedDir = directoryURL.standardizedFileURL
        let dotRunnerURL = standardizedDir.appending(path: ".runner")
        guard let rawData = try? Data(contentsOf: dotRunnerURL),
              let config = try? LocalDotRunnerConfig.decode(from: rawData)
        else {
            return nil
        }

        let workDir = standardizedDir.appending(path: config.workFolder, directoryHint: .isDirectory)
        let version = Self.detectRunnerVersion(in: standardizedDir)
        let rootPath = Self.normalizedDirectoryPath(for: standardizedDir)
        let procState = activeProcesses[rootPath]

        return DiscoveredLocalRunner(
            rootDirectory: standardizedDir,
            config: config,
            workDirectory: workDir,
            runnerVersion: version,
            listenerPID: procState?.listenerPID,
            isWorkerActive: procState?.isWorkerActive ?? false
        )
    }

    public func discoverAllLocalRunners(additionalDirectories: [URL] = []) -> [DiscoveredLocalRunner] {
        let activeProcesses = processTableProvider?() ?? queryLiveProcessTable()
        let home = homeDirectory

        // External folders are read only after explicit selection in NSOpenPanel.
        // A process-table entry is metadata, not consent to read its directory.
        var candidateDirs: [URL] = [home.appending(path: "actions-runner", directoryHint: .isDirectory)]

        // Also scan ~/.octorunner/runners/* if present
        for relativePath in [".octorunner/runners", "Library/Application Support/io.octorunner.macos/runners"] {
            let managedRunnersDir = home.appending(path: relativePath, directoryHint: .isDirectory)
            guard RunnerDirectoryAccessPolicy.allowsAutomaticRead(at: managedRunnersDir, homeDirectory: home) else { continue }
            if let children = try? FileManager.default.contentsOfDirectory(
                at: managedRunnersDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                candidateDirs.append(contentsOf: children)
            }
        }
        candidateDirs = candidateDirs.filter {
            RunnerDirectoryAccessPolicy.allowsAutomaticRead(at: $0.appending(path: ".runner"), homeDirectory: home)
        }
        // Explicit user selections may point outside standard roots.
        candidateDirs.append(contentsOf: additionalDirectories)

        var seenPaths: Set<String> = []
        var discovered: [DiscoveredLocalRunner] = []

        for dir in candidateDirs {
            let normPath = Self.normalizedDirectoryPath(for: dir)
            guard !seenPaths.contains(normPath) else { continue }
            seenPaths.insert(normPath)

            if let runner = inspectRunnerDirectory(at: dir, activeProcesses: activeProcesses) {
                discovered.append(runner)
            }
        }

        return discovered
    }

    private static func detectRunnerVersion(in directoryURL: URL) -> String? {
        let binSymlink = directoryURL.appending(path: "bin")
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: binSymlink.path()) {
            let lastComponent = URL(fileURLWithPath: destination).lastPathComponent
            if lastComponent.hasPrefix("bin.") {
                return String(lastComponent.dropFirst(4))
            }
        }
        return nil
    }
}
