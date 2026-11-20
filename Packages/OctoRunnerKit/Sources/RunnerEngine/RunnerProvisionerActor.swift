import CoreModels
import Darwin
import Foundation
import GitHubAPI
import SyncKit

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

    public func prepareMigration(_ request: RunnerMigrationRequest) async throws -> RunnerMigrationPlan {
        guard try migrationJournal.pending(request.runnerID) == nil else { throw RunnerMigrationError.recoveryRequired }
        return try await recheckMigration(request)
    }

    public func migrationRecovery(for runnerID: UUID) throws -> RunnerMigrationRecovery? {
        try migrationJournal.pending(runnerID)
    }

    public func migrationProtectedPaths() throws -> Set<String> {
        try migrationJournal.protectedPaths()
    }

    public func discardInterruptedMigrationPreparation(for runnerID: UUID) async throws {
        try await RunnerMigrationCoordinator(journal: migrationJournal).discardPreparation(for: runnerID, in: baseRunnersDirectory)
    }

    public func retryMigrationStartup(
        configuration: ManagedRunnerConfiguration, remoteID: Int64, scope: URL,
        labels: [String], accountKey: String, supervisor: RunnerSupervisorActor, launchAgents: RunnerLaunchAgentInspector?,
        commit: (@MainActor @Sendable (RunnerMigrationRecovery, RunnerMigrationRegistration) throws -> Void)? = nil
    ) async throws {
        guard configuration.mode == .direct || configuration.mode == .launchAgent,
              configuration.rootDirectory.deletingLastPathComponent().standardizedFileURL.path == baseRunnersDirectory.standardizedFileURL.path,
              RunnerMigrationSource.isGitHubScope(scope) else {
            throw RunnerMigrationError.recoveryRequired
        }
        let client = provisioningClient
        let verify: @Sendable (RunnerMigrationRecovery) async throws -> GitHubRemoteRunnerDTO = { entry in
            let loaded = try RunnerMigrationSource.inspect(entry.destination).configuration
            guard loaded.agentName == configuration.name, loaded.agentId == remoteID,
                  loaded.workFolder == "_work", RunnerMigrationPreflight.matchesScope(scope, actual: loaded.gitHubUrl),
                  entry.launchAgent == (configuration.mode == .launchAgent) else {
                throw RunnerMigrationError.runnerIdentityMismatch
            }
            let oauth = try await client.readToken(for: accountKey)
            let checks = RunnerMigrationGitHubChecks()
            let expected = RunnerMigrationPreflight.arm64MacLabels.union(labels.map { $0.lowercased() })
            guard let remote = try await checks.runner(for: loaded, token: oauth),
                  remote.id == remoteID, remote.name == loaded.agentName,
                  Set(remote.labelNames.map { $0.lowercased() }) == expected else {
                throw RunnerMigrationError.runnerNotAccessible
            }
            if remote.id != entry.oldRemoteID,
               try await !checks.previousRunnerIsAbsent(for: loaded, previousID: entry.oldRemoteID, token: oauth) {
                throw RunnerMigrationError.runnerIdentityMismatch
            }
            if loaded.inferredScopeType == .organization {
                guard let group = try await checks.group(for: loaded, runnerID: remoteID, token: oauth),
                      group.id == loaded.poolId, group.name == loaded.poolName else { throw RunnerMigrationError.groupChanged }
            }
            return remote
        }
        let finalize: (@Sendable (RunnerMigrationRecovery) async throws -> Void)?
        if let commit {
            finalize = { entry in
                let remote = try await verify(entry)
                guard let version = entry.version, remote.status == "offline", !remote.busy else {
                    throw RunnerMigrationError.recoveryRequired
                }
                try await commit(entry, .init(remoteID: remoteID, version: version))
            }
        } else {
            finalize = nil
        }
        try await RunnerMigrationCoordinator(journal: migrationJournal).retryStartup(
            for: configuration.runnerID, destination: configuration.rootDirectory, remoteID: remoteID, commit: finalize
        ) { entry in
            let remote = try await verify(entry)
            try await RunnerMigrationStartup.start(
                runnerID: entry.runnerID, name: configuration.name, original: entry.source, destination: entry.destination,
                launchInBackground: configuration.mode == .launchAgent, launch: configuration.launch,
                supervisor: supervisor, launchAgents: launchAgents, mayLaunchNewProcess: remote.status == "offline" && !remote.busy
            )
        }
    }

    public func confirmMigration(
        _ plan: RunnerMigrationPlan,
        launch: RunnerLaunchConfiguration,
        supervisor: RunnerSupervisorActor,
        launchAgents: RunnerLaunchAgentInspector?,
        commit: @escaping @MainActor @Sendable (RunnerMigrationRegistration) throws -> Void
    ) async throws {
        guard !plan.launchAgent || launchAgents != nil else { throw RunnerSupervisionError.notManaged }
        let operations = RunnerProvisioningMigrationOperations(
            plan: plan, launch: launch, provisioning: provisioningClient, binaryCache: binaryCache,
            supervisor: supervisor, launchAgents: launchAgents, commit: commit,
            preflight: { try await self.recheckMigration($0) }
        )
        _ = try await RunnerMigrationCoordinator(journal: migrationJournal).migrate(plan, operations: operations)
    }

    private var migrationJournal: RunnerMigrationJournal {
        RunnerMigrationJournal(directory: baseRunnersDirectory.deletingLastPathComponent()
            .appending(path: "migration-journals", directoryHint: .isDirectory))
    }

    // Only the coordinator may recheck a plan after reserving its journal.
    private func recheckMigration(_ request: RunnerMigrationRequest) async throws -> RunnerMigrationPlan {
        let client = provisioningClient
        let checks = RunnerMigrationGitHubChecks()
        let sampler = RunnerProcessSampler()
        let preflight = RunnerMigrationPreflight(
            baseRunnersDirectory: baseRunnersDirectory,
            fetchRemote: { config, account in
                let token = try await client.readToken(for: account)
                return try await checks.runner(for: config, token: token)
            },
            fetchGroup: { config, account, runnerID in
                let token = try await client.readToken(for: account)
                return try await checks.group(for: config, runnerID: runnerID, token: token)
            },
            sampleProcesses: { try await sampler.sample() }
        )
        return try await preflight.prepare(request)
    }

    public func provisionRunners(
        instanceNames: [String],
        scopeType: RunnerScopeType,
        scopeURL: URL,
        labels: [String],
        registerLaunchAgent: Bool,
        accessToken: String,
        configuration: RunnerLaunchConfiguration = RunnerLaunchConfiguration(),
        onStatusUpdate: @MainActor @Sendable (RunnerProvisioningProgress) -> Void
    ) async throws -> [ProvisionedRunnerSummary] {
        for name in instanceNames {
            try Self.validateRunnerName(name)
        }
        await onStatusUpdate(.fetchingMetadata)
        let candidate = try await provisioningClient.fetchArm64RunnerDownload(
            scopeURL: scopeURL,
            token: accessToken
        )

        let version = Self.extractVersion(fromFilename: candidate.filename) ?? "latest"
        await onStatusUpdate(.verifyingBinary(filename: candidate.filename))
        let archiveURL = try await binaryCache.ensureBinaryDownloadedAndVerified(package: candidate)

        let baseDir = self.baseRunnersDirectory
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        await onStatusUpdate(.registeringInstances(count: instanceNames.count))
        let client = self.provisioningClient

        return try await withThrowingTaskGroup(of: ProvisionedRunnerSummary.self) { group in
            for instanceName in instanceNames {
                group.addTask {
                    let tokenDTO = try await client.createRegistrationToken(
                        scopeURL: scopeURL,
                        token: accessToken
                    )
                    let instanceRoot = try Self.createInstanceDirectory(name: instanceName, in: baseDir)
                    let workDir = instanceRoot.appending(path: "_work", directoryHint: .isDirectory)
                    let diagDir = instanceRoot.appending(path: "_diag", directoryHint: .isDirectory)
                    do {
                        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
                        try FileManager.default.createDirectory(at: diagDir, withIntermediateDirectories: true)
                        try await Self.extractArchive(archiveURL: archiveURL, into: instanceRoot)
                    } catch {
                        // The registration command has not run, so this newly
                        // reserved directory has no registered listener to preserve.
                        try? FileManager.default.removeItem(at: instanceRoot)
                        throw error
                    }
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
                        let label = RunnerServiceLabel.forRunner(named: instanceName)
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
                        launchedPID = try await Self.bootstrapLaunchAgent(plistURL: plistURL)
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

    static func createInstanceDirectory(name: String, in base: URL) throws -> URL {
        try validateRunnerName(name)
        let root = base.appending(path: name, directoryHint: .isDirectory)
        guard mkdir(root.path, 0o700) == 0 else {
            if errno == EEXIST { throw RunnerEngineError.runnerDirectoryAlreadyExists }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return root
    }

    static func validateRunnerName(_ name: String) throws {
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
        configuration: RunnerLaunchConfiguration,
        runnerGroup: String? = nil
    ) async throws {
        let configScript = instanceRoot.appending(path: "config.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = instanceRoot
        process.arguments = [
            configScript.path(percentEncoded: false),
            "--unattended",
            "--url", scopeURL.absoluteString,
            "--name", runnerName,
            "--labels", labels.joined(separator: ","),
            "--work", "_work",
            "--replace"
        ]
        var environment = ProcessInfo.processInfo.environment.merging(configuration.environment) { _, configured in configured }
        environment = environment.filter { !$0.key.uppercased().hasPrefix("ACTIONS_RUNNER_INPUT_") }
        environment["ACTIONS_RUNNER_INPUT_TOKEN"] = registrationToken
        environment["ACTIONS_RUNNER_INPUT_RUNNERGROUP"] = runnerGroup
        process.environment = environment
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

    static func bootstrapLaunchAgent(plistURL: URL, executableURL: URL = URL(fileURLWithPath: "/bin/launchctl")) async throws -> Int32? {
        let uid = getuid()
        let bootstrap = Process()
        bootstrap.executableURL = executableURL
        bootstrap.arguments = ["bootstrap", "gui/\(uid)", plistURL.path(percentEncoded: false)]
        bootstrap.standardInput = FileHandle.nullDevice
        bootstrap.standardOutput = FileHandle.nullDevice
        bootstrap.standardError = FileHandle.nullDevice
        let status = try await ConfigurationProcessRunner.run(bootstrap)
        guard status == 0 else {
            throw RunnerEngineError.launchAgentRegistrationFailed(status, "The service was not registered. Registration output was omitted.")
        }
        return nil
    }

}
