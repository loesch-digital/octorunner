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
        configuration: RunnerLaunchConfiguration = RunnerLaunchConfiguration(),
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> [ProvisionedRunnerSummary] {
        for name in instanceNames {
            try Self.validateRunnerName(name)
        }
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

                    try await Self.extractArchive(archiveURL: archiveURL, into: instanceRoot)
                    try await Self.runConfigScript(
                        in: instanceRoot,
                        scopeURL: scopeURL,
                        registrationToken: tokenDTO.token,
                        runnerName: instanceName,
                        labels: labels,
                        configuration: configuration
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
                            runnerRootDirectory: instanceRoot,
                            configuration: configuration
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
                        launchedPID = Self.spawnDetachedRunnerProcess(in: instanceRoot, configuration: configuration)
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

    /// Migrates an existing local runner directory (e.g. `~/Documents/apps/actions-runner`) into OctoRunner's managed directory
    /// (`~/Library/Application Support/io.octorunner.macos/runners/<name>`) and optionally registers its LaunchAgent.
    public func migrateImportedRunnerDirectory(
        runnerName: String,
        sourceRootDirectory: URL,
        registerLaunchAgent: Bool,
        configuration: RunnerLaunchConfiguration = RunnerLaunchConfiguration()
    ) throws -> URL {
        try Self.validateRunnerName(runnerName)
        try FileManager.default.createDirectory(at: baseRunnersDirectory, withIntermediateDirectories: true)
        let destinationRoot = baseRunnersDirectory.appending(path: runnerName, directoryHint: .isDirectory)

        if sourceRootDirectory.standardizedFileURL != destinationRoot.standardizedFileURL {
            if FileManager.default.fileExists(atPath: destinationRoot.path(percentEncoded: false)) {
                throw RunnerEngineError.runnerDirectoryAlreadyExists
            }
            try FileManager.default.copyItem(at: sourceRootDirectory, to: destinationRoot)
        }

        let workDir = destinationRoot.appending(path: "_work", directoryHint: .isDirectory)
        let diagDir = destinationRoot.appending(path: "_diag", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: diagDir, withIntermediateDirectories: true)

        if registerLaunchAgent {
            let sanitized = runnerName.lowercased().replacingOccurrences(of: " ", with: "-")
            let label = "io.octorunner.agent.\(sanitized)"
            let plistData = try LaunchAgentPlistGenerator.generatePlistData(
                serviceLabel: label,
                runnerRootDirectory: destinationRoot,
                configuration: configuration
            )
            let plistURL = LaunchAgentPlistGenerator.launchAgentPlistURL(for: label)
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try plistData.write(to: plistURL, options: .atomic)
            _ = Self.bootstrapLaunchAgent(plistURL: plistURL)
        }

        return destinationRoot
    }

    private static func validateRunnerName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", name.utf8.count <= 200,
              !name.contains("/"), !name.contains("\\"),
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw RunnerEngineError.invalidRunnerName
        }
    }

    public static func extractVersion(fromFilename filename: String) -> String? {
        let stripped = filename
            .replacingOccurrences(of: "actions-runner-osx-arm64-", with: "")
            .replacingOccurrences(of: "actions-runner-osx-x64-", with: "")
            .replacingOccurrences(of: ".tar.gz", with: "")
        return stripped.isEmpty ? nil : stripped
    }

    static func extractArchive(archiveURL: URL, into destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archiveURL.path(percentEncoded: false), "-C", destination.path(percentEncoded: false)]
        let status = try await ConfigurationProcessRunner.run(process)

        guard status == 0 else {
            throw RunnerEngineError.extractionFailed(status)
        }
    }

    static func runConfigScript(
        in instanceRoot: URL,
        scopeURL: URL,
        registrationToken: String,
        runnerName: String,
        labels: [String],
        configuration: RunnerLaunchConfiguration
    ) async throws {
        let configScript = instanceRoot.appending(path: "config.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = instanceRoot
        process.arguments = [
            configScript.path(percentEncoded: false),
            "--unattended",
            "--url", scopeURL.absoluteString,
            "--token", registrationToken,
            "--name", runnerName,
            "--labels", labels.joined(separator: ","),
            "--work", "_work",
            "--replace"
        ]
        process.environment = ProcessInfo.processInfo.environment.merging(configuration.environment) { _, configured in configured }
        // Unattended setup has no interactive input. Its output can contain the
        // registration credential, so never retain it in errors or diagnostic logs.
        // Null handles also avoid filling an undrained pipe while awaiting exit.
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let status = try await ConfigurationProcessRunner.run(process)

        guard status == 0 else {
            throw RunnerEngineError.configurationFailed(
                status,
                "Configuration output was omitted to protect registration credentials."
            )
        }
    }

    private static func bootstrapLaunchAgent(plistURL: URL) -> Int32? {
        let uid = getuid()
        let bootstrap = Process()
        bootstrap.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootstrap.arguments = ["bootstrap", "gui/\(uid)", plistURL.path(percentEncoded: false)]
        try? bootstrap.run()
        bootstrap.waitUntilExit()
        return nil
    }

    private static func spawnDetachedRunnerProcess(in instanceRoot: URL, configuration: RunnerLaunchConfiguration) -> Int32? {
        let runScript = instanceRoot.appending(path: "run.sh")
        guard FileManager.default.fileExists(atPath: runScript.path(percentEncoded: false)) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = instanceRoot
        process.arguments = [runScript.path(percentEncoded: false)]
        process.environment = ProcessInfo.processInfo.environment.merging(configuration.environment) { _, configured in configured }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        return process.isRunning ? process.processIdentifier : nil
    }
}
