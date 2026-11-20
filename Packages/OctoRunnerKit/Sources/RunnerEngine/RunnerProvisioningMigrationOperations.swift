import Darwin
import Foundation
import GitHubAPI
import SyncKit

public struct RunnerMigrationRegistration: Sendable {
    public let remoteID: Int64
    public let version: String
}

actor RunnerProvisioningMigrationOperations: RunnerMigrationOperations {
    private let plan: RunnerMigrationPlan
    private let launch: RunnerLaunchConfiguration
    private let provisioning: GitHubRunnerProvisioningClient
    private let binaryCache: RunnerBinaryCacheActor
    private let supervisor: RunnerSupervisorActor
    private let launchAgents: RunnerLaunchAgentInspector?
    private let apply: @MainActor @Sendable (RunnerMigrationRegistration) throws -> Void
    private let preflight: @Sendable (RunnerMigrationRequest) async throws -> RunnerMigrationPlan
    private let github = RunnerMigrationGitHubChecks()
    private var registrationToken: String?
    private var version: String?

    init(
        plan: RunnerMigrationPlan,
        launch: RunnerLaunchConfiguration,
        provisioning: GitHubRunnerProvisioningClient,
        binaryCache: RunnerBinaryCacheActor,
        supervisor: RunnerSupervisorActor,
        launchAgents: RunnerLaunchAgentInspector?,
        commit: @escaping @MainActor @Sendable (RunnerMigrationRegistration) throws -> Void,
        preflight: @escaping @Sendable (RunnerMigrationRequest) async throws -> RunnerMigrationPlan
    ) {
        self.plan = plan
        self.launch = launch
        self.provisioning = provisioning
        self.binaryCache = binaryCache
        self.supervisor = supervisor
        self.launchAgents = launchAgents
        self.apply = commit
        self.preflight = preflight
    }

    func stage(at destination: URL) async throws -> String {
        let oauth = try await provisioning.readToken(for: plan.request.accountKey)
        let download = try await provisioning.fetchArm64RunnerDownload(scopeURL: plan.scope, token: oauth)
        let archive = try await binaryCache.ensureBinaryDownloadedAndVerified(package: download)
        guard let installedVersion = RunnerProvisionerActor.extractVersion(fromFilename: download.filename) else {
            throw RunnerMigrationError.runnerIdentityMismatch
        }
        for child in ["_work", "_diag"] {
            try FileManager.default.createDirectory(at: destination.appending(path: child), withIntermediateDirectories: false)
        }
        try await RunnerProvisionerActor.extractArchive(archiveURL: archive, into: destination)
        version = installedVersion
        return installedVersion
    }

    func verifyBeforeRegistration() async throws {
        let label = RunnerServiceLabel.forRunner(named: plan.runnerName)
        var definition = stat()
        guard lstat(LaunchAgentPlistGenerator.launchAgentPlistURL(for: label).path, &definition) == -1,
              errno == ENOENT,
              try await LaunchAgentServiceStateReader().isUnloaded(label: label) else {
            throw RunnerMigrationError.conflictingService
        }
        let oauth = try await provisioning.readToken(for: plan.request.accountKey)
        let token = try await provisioning.createRegistrationToken(scopeURL: plan.scope, token: oauth)
        let fresh = try await preflight(plan.request)
        guard fresh.source == plan.source else { throw RunnerMigrationError.sourceChanged }
        guard fresh.group == plan.group else { throw RunnerMigrationError.groupChanged }
        guard Set(fresh.customLabels) == Set(plan.customLabels) else { throw RunnerMigrationError.labelsChanged }
        registrationToken = token.token
    }

    func register() async throws -> Int64 {
        guard let token = registrationToken else { throw RunnerMigrationError.runnerNotAccessible }
        registrationToken = nil
        try await RunnerProvisionerActor.runConfigScript(
            in: plan.destination, scopeURL: plan.scope, registrationToken: token,
            runnerName: plan.runnerName, labels: plan.customLabels, configuration: launch,
            runnerGroup: plan.group?.name
        )
        let configured = try RunnerMigrationSource.inspect(plan.destination).configuration
        guard configured.agentName == plan.runnerName,
              configured.ownerAndRepo?.owner.lowercased() == plan.source.configuration.ownerAndRepo?.owner.lowercased(),
              configured.ownerAndRepo?.repo?.lowercased() == plan.source.configuration.ownerAndRepo?.repo?.lowercased(),
              configured.workFolder == "_work" else { throw RunnerMigrationError.runnerIdentityMismatch }
        let oauth = try await provisioning.readToken(for: plan.request.accountKey)
        let expectedLabels = RunnerMigrationPreflight.arm64MacLabels.union(plan.customLabels.map { $0.lowercased() })
        guard let remote = try await github.runner(for: configured, token: oauth),
              remote.id == configured.agentId, remote.name == plan.runnerName,
              remote.status == "offline", !remote.busy,
              Set(remote.labelNames.map { $0.lowercased() }) == expectedLabels else {
            throw RunnerMigrationError.runnerIdentityMismatch
        }
        if remote.id != plan.request.remoteRunnerID,
           try await !github.previousRunnerIsAbsent(for: plan.source.configuration, token: oauth) {
            throw RunnerMigrationError.runnerIdentityMismatch
        }
        if let group = plan.group {
            guard try await github.group(for: configured, runnerID: remote.id, token: oauth) == group else {
                throw RunnerMigrationError.groupChanged
            }
        }
        return remote.id
    }

    func commit(newRemoteID: Int64) async throws {
        guard let version else { throw RunnerMigrationError.recoveryRequired }
        try await apply(.init(remoteID: newRemoteID, version: version))
    }

    func start() async throws {
        try plan.source.revalidate()
        try await RunnerMigrationStartup.start(
            runnerID: plan.runnerID, name: plan.runnerName, original: plan.sourceDirectory, destination: plan.destination,
            launchInBackground: plan.launchAgent, launch: launch, supervisor: supervisor, launchAgents: launchAgents,
            mayLaunchNewProcess: true
        )
    }
}

enum RunnerMigrationStartup {
    static func start(runnerID: UUID, name: String, original: URL, destination: URL, launchInBackground: Bool,
                      launch: RunnerLaunchConfiguration, supervisor: RunnerSupervisorActor,
                      launchAgents: RunnerLaunchAgentInspector?, mayLaunchNewProcess: Bool) async throws {
        try await RunnerMigrationPreflight.checkSourceProcesses(original, sampling: { try await RunnerProcessSampler().sample() })
        var originalInfo = stat()
        if lstat(original.path, &originalInfo) == 0 {
            _ = try RunnerMigrationSource.inspect(original)
        } else if errno != ENOENT {
            throw RunnerMigrationError.unverifiedSource
        }
        if launchInBackground {
            guard let launchAgents else { throw RunnerSupervisionError.notManaged }
            let label = RunnerServiceLabel.forRunner(named: name)
            let target = RunnerLaunchAgentTarget(name: name, rootDirectory: destination, label: label)
            let definition = try await launchAgents.inspect(target)
            if definition.definition == .verified {
                switch try await launchAgents.runtime(target) {
                case .running: return
                case .unloaded: break
                case .loaded, .unverified: throw RunnerMigrationError.conflictingService
                }
            } else if definition.definition != .missing {
                throw RunnerMigrationError.conflictingService
            }
            guard mayLaunchNewProcess else { throw RunnerMigrationError.listenerStillRunning }
            if definition.definition == .missing {
                guard try await LaunchAgentServiceStateReader().isUnloaded(label: label) else {
                    throw RunnerMigrationError.conflictingService
                }
                try Self.installDefinition(target: target, launch: launch)
            }
            try await launchAgents.loadDefinition(target)
        } else {
            try await supervisor.configure(.init(runnerID: runnerID, name: name,
                                                rootDirectory: destination, mode: .direct, launch: launch))
            if !mayLaunchNewProcess {
                guard await supervisor.snapshot(runnerID: runnerID)?.pid != nil else {
                    throw RunnerMigrationError.listenerStillRunning
                }
                return
            }
            try await supervisor.start(runnerID: runnerID)
        }
    }

    private static func installDefinition(target: RunnerLaunchAgentTarget, launch: RunnerLaunchConfiguration) throws {
        let url = LaunchAgentPlistGenerator.launchAgentPlistURL(for: target.label)
        let plist = try LaunchAgentPlistGenerator.generatePlistData(
            serviceLabel: target.label, runnerRootDirectory: target.rootDirectory, configuration: launch
        )
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staged = directory.appending(path: ".octorunner-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: staged) }
        try plist.write(to: staged, options: .withoutOverwriting)
        guard link(staged.path, url.path) == 0 else { throw RunnerMigrationError.conflictingService }
    }
}
