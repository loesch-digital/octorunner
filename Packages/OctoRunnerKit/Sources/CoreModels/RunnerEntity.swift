import Foundation
import SwiftData

@Model
public final class RunnerEntity {
    #Index<RunnerEntity>([\.statusRaw], [\.name])

    public var id: UUID = UUID()
    public var name: String = ""
    public var githubRunnerId: Int64?
    public var scopeTypeRaw: String = RunnerScopeType.repository.rawValue
    public var scopeUrlString: String = ""
    public var statusRaw: String = RunnerStatus.offline.rawValue
    public var labels: [String] = []
    public var workDirectoryPath: String = ""
    public var rootDirectoryPath: String?
    public var runnerVersion: String?
    public var isImportedLocal: Bool = false
    public var executionModeRaw: String? = nil
    public var serviceLabel: String = ""
    public var currentJobName: String?
    public var currentRepo: String?
    public var lastHeartbeat: Date = Date.now
    public var pid: Int32?

    @Relationship(deleteRule: .cascade, inverse: \JobRunEntity.runner)
    public var jobRuns: [JobRunEntity] = []

    public var status: RunnerStatus {
        get { RunnerStatus(rawValue: statusRaw) ?? .offline }
        set { statusRaw = newValue.rawValue }
    }

    public var scopeType: RunnerScopeType {
        get { RunnerScopeType(rawValue: scopeTypeRaw) ?? .repository }
        set { scopeTypeRaw = newValue.rawValue }
    }

    /// Legacy data may contain a generated service label without an installed
    /// service. Only an explicit record establishes an OctoRunner-owned mode.
    public var executionMode: RunnerExecutionMode? {
        get { isImportedLocal ? .external : executionModeRaw.flatMap(RunnerExecutionMode.init(rawValue:)) }
        set { executionModeRaw = isImportedLocal ? RunnerExecutionMode.external.rawValue : newValue?.rawValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        scopeType: RunnerScopeType = .repository,
        scopeUrl: URL,
        status: RunnerStatus = .idle,
        labels: [String] = ["self-hosted", "macos", "arm64", "apple-silicon"],
        workDirectory: URL,
        rootDirectoryPath: String? = nil,
        runnerVersion: String? = nil,
        isImportedLocal: Bool = false,
        pid: Int32? = nil,
        executionMode: RunnerExecutionMode? = nil
    ) {
        self.id = id
        self.name = name
        self.githubRunnerId = nil
        self.scopeTypeRaw = scopeType.rawValue
        self.scopeUrlString = scopeUrl.absoluteString
        self.statusRaw = status.rawValue
        self.labels = labels
        self.workDirectoryPath = workDirectory.path(percentEncoded: false)
        self.rootDirectoryPath = rootDirectoryPath ?? workDirectory.deletingLastPathComponent().path(percentEncoded: false)
        self.runnerVersion = runnerVersion
        self.isImportedLocal = isImportedLocal
        self.executionModeRaw = isImportedLocal ? RunnerExecutionMode.external.rawValue : executionMode?.rawValue
        self.serviceLabel = "io.octorunner.agent.\(name)"
        self.currentJobName = nil
        self.currentRepo = nil
        self.lastHeartbeat = .now
        self.pid = pid
        self.jobRuns = []
    }
}
