import CoreModels
import Foundation
import GitHubAPI

public struct ProvisionedRunnerSummary: Sendable, Equatable {
    public let name: String
    public let scopeType: RunnerScopeType
    public let scopeURL: URL
    public let rootDirectory: URL
    public let workDirectory: URL
    public let labels: [String]
    public let runnerVersion: String
    public let launchdLabel: String?
    public let pid: Int32?

    public init(
        name: String,
        scopeType: RunnerScopeType,
        scopeURL: URL,
        rootDirectory: URL,
        workDirectory: URL,
        labels: [String],
        runnerVersion: String,
        launchdLabel: String?,
        pid: Int32?
    ) {
        self.name = name
        self.scopeType = scopeType
        self.scopeURL = scopeURL
        self.rootDirectory = rootDirectory
        self.workDirectory = workDirectory
        self.labels = labels
        self.runnerVersion = runnerVersion
        self.launchdLabel = launchdLabel
        self.pid = pid
    }
}

/// Provisions 1..N GitHub Actions runner instances concurrently using `withThrowingTaskGroup`.
public actor RunnerProvisionerActor {
    private let provisioningClient: GitHubRunnerProvisioningClient
    private let binaryCache: RunnerBinaryCacheActor
    private let baseRunnersDirectory: URL

    public init(
        provisioningClient: GitHubRunnerProvisioningClient = GitHubRunnerProvisioningClient(),
        binaryCache: RunnerBinaryCacheActor = RunnerBinaryCacheActor(),
        baseRunnersDirectory: URL? = nil
    ) {
        self.provisioningClient = provisioningClient
        self.binaryCache = binaryCache
        if let baseRunnersDirectory {
            self.baseRunnersDirectory = baseRunnersDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
            self.baseRunnersDirectory = appSupport.appending(path: "io.octorunner.macos/runners", directoryHint: .isDirectory)
        }
    }

    public func provisionRunners(
        instanceNames: [String],
        scopeType: RunnerScopeType,
        scopeURL: URL,
        labels: [String],
        registerLaunchAgent: Bool,
        accessToken: String,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> [ProvisionedRunnerSummary] {
        await onStatusUpdate("Fetching macOS ARM64 runner binary metadata from GitHub…")
        let candidate = try await provisioningClient.fetchArm64RunnerDownload(
            scopeURL: scopeURL,
            token: accessToken
        )

        let version = Self.extractVersion(fromFilename: candidate.filename) ?? "latest"
        await onStatusUpdate("Ensuring verified runner binary (\(candidate.filename)) in cache…")
        let archiveURL = try await binaryCache.ensureBinaryDownloadedAndVerified(package: candidate)

        let baseDir = self.baseRunnersDirectory
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        await onStatusUpdate("Provisioning \(instanceNames.count) runner instance(s) in parallel…")
        let client = self.provisioningClient

        return try await withThrowingTaskGroup(of: ProvisionedRunnerSummary.self) { group in
            for instanceName in instanceNames {
                group.addTask {
                    let tokenDTO = try await client.createRegistrationToken(
                        scopeURL: scopeURL,
                        token: accessToken
                    )
                    let instanceRoot = baseDir.appending(path: instanceName, directoryHint: .isDirectory)
                    let workDir = instanceRoot.appending(path: "_work", directoryHint: .isDirectory)
                    let diagDir = instanceRoot.appending(path: "_diag", directoryHint: .isDirectory)
                    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: diagDir, withIntermediateDirectories: true)

                    try Self.extractArchive(archiveURL: archiveURL, into: instanceRoot)
                    try Self.runConfigScript(
                        in: instanceRoot,
                        scopeURL: scopeURL,
                        registrationToken: tokenDTO.token,
                        runnerName: instanceName,
                        labels: labels
                    )

                    var launchdLabel: String?
                    var launchedPID: Int32?

                    if registerLaunchAgent {
                        let sanitized = instanceName
                            .lowercased()
                            .replacingOccurrences(of: " ", with: "-")
                        let label = "io.octorunner.agent.\(sanitized)"
                        let plistData = try LaunchAgentPlistGenerator.generatePlistData(
                            serviceLabel: label,
                            runnerRootDirectory: instanceRoot
                        )
                        let plistURL = LaunchAgentPlistGenerator.launchAgentPlistURL(for: label)
                        try FileManager.default.createDirectory(
                            at: plistURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try plistData.write(to: plistURL, options: .atomic)
                        launchdLabel = label
                        launchedPID = Self.bootstrapLaunchAgent(plistURL: plistURL)
                    } else {
                        launchedPID = Self.spawnDetachedRunnerProcess(in: instanceRoot)
                    }

                    return ProvisionedRunnerSummary(
                        name: instanceName,
                        scopeType: scopeType,
                        scopeURL: scopeURL,
                        rootDirectory: instanceRoot,
                        workDirectory: workDir,
                        labels: labels,
                        runnerVersion: version,
                        launchdLabel: launchdLabel,
                        pid: launchedPID
                    )
                }
            }

            var provisioned: [ProvisionedRunnerSummary] = []
            for try await summary in group {
                provisioned.append(summary)
            }
            return provisioned.sorted { $0.name < $1.name }
        }
    }

    public static func extractVersion(fromFilename filename: String) -> String? {
        let stripped = filename
            .replacingOccurrences(of: "actions-runner-osx-arm64-", with: "")
            .replacingOccurrences(of: "actions-runner-osx-x64-", with: "")
            .replacingOccurrences(of: ".tar.gz", with: "")
        return stripped.isEmpty ? nil : stripped
    }

    private static func extractArchive(archiveURL: URL, into destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archiveURL.path(), "-C", destination.path()]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw RunnerEngineError.extractionFailed(process.terminationStatus)
        }
    }

    private static func runConfigScript(
        in instanceRoot: URL,
        scopeURL: URL,
        registrationToken: String,
        runnerName: String,
        labels: [String]
    ) throws {
        let configScript = instanceRoot.appending(path: "config.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = instanceRoot
        process.arguments = [
            configScript.path(),
            "--unattended",
            "--url", scopeURL.absoluteString,
            "--token", registrationToken,
            "--name", runnerName,
            "--labels", labels.joined(separator: ","),
            "--work", "_work",
            "--replace"
        ]
        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let combined = (String(data: outData, encoding: .utf8) ?? "") + "\n" + (String(data: errData, encoding: .utf8) ?? "")
            throw RunnerEngineError.configurationFailed(
                process.terminationStatus,
                combined.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func bootstrapLaunchAgent(plistURL: URL) -> Int32? {
        let uid = getuid()
        let bootstrap = Process()
        bootstrap.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootstrap.arguments = ["bootstrap", "gui/\(uid)", plistURL.path()]
        try? bootstrap.run()
        bootstrap.waitUntilExit()
        return nil
    }

    private static func spawnDetachedRunnerProcess(in instanceRoot: URL) -> Int32? {
        let runScript = instanceRoot.appending(path: "run.sh")
        guard FileManager.default.fileExists(atPath: runScript.path()) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = instanceRoot
        process.arguments = [runScript.path()]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        return process.isRunning ? process.processIdentifier : nil
    }
}
