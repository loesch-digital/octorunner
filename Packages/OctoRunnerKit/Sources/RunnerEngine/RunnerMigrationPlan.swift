import Darwin
import Foundation
import SyncKit

public struct RunnerMigrationRequest: Sendable {
    public let runnerID: UUID
    public let name: String
    public let remoteRunnerID: Int64
    public let sourceDirectory: URL
    public let scope: URL
    public let labels: [String]
    public let accountKey: String
    public let launchAgent: Bool

    public init(runnerID: UUID, name: String, remoteRunnerID: Int64, sourceDirectory: URL,
                scope: URL, labels: [String], accountKey: String, launchAgent: Bool) {
        self.runnerID = runnerID
        self.name = name
        self.remoteRunnerID = remoteRunnerID
        self.sourceDirectory = sourceDirectory
        self.scope = scope
        self.labels = labels
        self.accountKey = accountKey
        self.launchAgent = launchAgent
    }
}

public struct RunnerMigrationGroup: Equatable, Sendable {
    public let id: Int
    public let name: String
}

public struct RunnerMigrationPlan: Sendable {
    public var runnerID: UUID { request.runnerID }
    public var runnerName: String { request.name }
    public var sourceDirectory: URL { source.rootDirectory }
    public var scope: URL { source.configuration.gitHubUrl }
    public var launchAgent: Bool { request.launchAgent }
    public let destination: URL
    public let group: RunnerMigrationGroup?
    public let customLabels: [String]
    let request: RunnerMigrationRequest
    let source: RunnerMigrationSource
}

/// Checks both sides of a migration without creating files or changing the registration.
actor RunnerMigrationPreflight {
    static let arm64MacLabels: Set<String> = ["self-hosted", "macos", "arm64"]
    private let baseRunnersDirectory: URL
    private let fetchRemote: @Sendable (LocalDotRunnerConfig, String) async throws -> GitHubRemoteRunnerDTO?
    private let fetchGroup: @Sendable (LocalDotRunnerConfig, String, Int64) async throws -> RunnerMigrationGroup?
    private let sampleProcesses: @Sendable () async throws -> [String: RunnerProcessPresence]

    init(
        baseRunnersDirectory: URL,
        fetchRemote: @escaping @Sendable (LocalDotRunnerConfig, String) async throws -> GitHubRemoteRunnerDTO?,
        fetchGroup: @escaping @Sendable (LocalDotRunnerConfig, String, Int64) async throws -> RunnerMigrationGroup?,
        sampleProcesses: @escaping @Sendable () async throws -> [String: RunnerProcessPresence]
    ) {
        self.baseRunnersDirectory = baseRunnersDirectory
        self.fetchRemote = fetchRemote
        self.fetchGroup = fetchGroup
        self.sampleProcesses = sampleProcesses
    }

    func prepare(_ request: RunnerMigrationRequest) async throws -> RunnerMigrationPlan {
        try RunnerProvisionerActor.validateRunnerName(request.name)
        let source = try RunnerMigrationSource.inspect(request.sourceDirectory)
        let config = source.configuration
        guard config.agentId == request.remoteRunnerID, config.agentName == request.name,
              Self.matchesScope(request.scope, actual: config.gitHubUrl) else {
            throw RunnerMigrationError.runnerIdentityMismatch
        }
        let destination = baseRunnersDirectory.appending(path: request.name, directoryHint: .isDirectory)
        try Self.checkDestination(destination)
        guard !request.accountKey.isEmpty,
              let remote = try await fetchRemote(config, request.accountKey) else {
            throw RunnerMigrationError.runnerNotAccessible
        }
        try Task.checkCancellation()
        guard remote.id == config.agentId, remote.name == config.agentName else {
            throw RunnerMigrationError.runnerIdentityMismatch
        }
        guard !remote.busy else { throw RunnerMigrationError.runnerBusy }
        guard remote.status == "offline" else { throw RunnerMigrationError.listenerStillRunning }

        let customLabels = try Self.checkedLabels(remote.labels, saved: request.labels)
        let group: RunnerMigrationGroup?
        if config.inferredScopeType == .organization {
            guard let id = config.poolId, id > 0, let name = config.poolName, !name.isEmpty,
                  let remoteGroup = try await fetchGroup(config, request.accountKey, remote.id),
                  remoteGroup.id == id, remoteGroup.name == name else {
                throw RunnerMigrationError.groupChanged
            }
            group = remoteGroup
        } else {
            group = nil
        }

        try await Self.checkSourceProcesses(source.rootDirectory, sampling: sampleProcesses)
        try source.revalidate()
        try Self.checkDestination(destination)
        return RunnerMigrationPlan(destination: destination, group: group, customLabels: customLabels,
                                   request: request, source: source)
    }

    static func checkSourceProcesses(_ root: URL,
                                     sampling: @Sendable () async throws -> [String: RunnerProcessPresence]) async throws {
        let processes = try await sampling()
        let paths = Set([
            LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: root),
            LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: root.resolvingSymlinksInPath())
        ])
        for path in paths {
            guard let presence = processes[path] else { continue }
            if presence.isWorkerActive { throw RunnerMigrationError.runnerBusy }
            if presence.listenerPID != nil { throw RunnerMigrationError.listenerStillRunning }
        }
    }

    static func matchesScope(_ expected: URL, actual: URL) -> Bool {
        guard RunnerMigrationSource.isGitHubScope(expected) else { return false }
        func scopePath(_ url: URL) -> [String] {
            url.path.split(separator: "/").map { $0.lowercased() }
        }
        return scopePath(expected) == scopePath(actual)
    }

    private static func checkDestination(_ destination: URL) throws {
        var info = stat()
        if lstat(destination.path, &info) == 0 {
            throw RunnerEngineError.runnerDirectoryAlreadyExists
        }
        guard errno == ENOENT else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func checkedLabels(_ remote: [GitHubRunnerLabelDTO], saved: [String]) throws -> [String] {
        let builtIn = Set(remote.filter { $0.type == "read-only" }.map { $0.name.lowercased() })
        guard builtIn == arm64MacLabels else { throw RunnerMigrationError.incompatibleRunnerLabels }
        let custom = remote.filter { $0.type == "custom" }.map(\.name)
        guard builtIn.count + custom.count == remote.count,
              Set(saved.map { $0.lowercased() }).subtracting(builtIn) == Set(custom.map { $0.lowercased() }),
              custom.allSatisfy({ label in
                  !label.isEmpty && !label.contains(",")
                      && label == label.trimmingCharacters(in: .whitespacesAndNewlines)
                      && label.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
              }) else {
            throw RunnerMigrationError.labelsChanged
        }
        return custom
    }
}
