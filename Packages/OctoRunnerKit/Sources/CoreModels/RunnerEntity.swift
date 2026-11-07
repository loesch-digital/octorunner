import Foundation
import SwiftData

@Model
public final class RunnerEntity {
    #Index<RunnerEntity>([\.statusRaw], [\.name])

    public var id: UUID
    public var name: String
    public var githubRunnerId: Int64?
    public var scopeTypeRaw: String
    public var scopeUrlString: String
    public var statusRaw: String
    public var labels: [String]
    public var workDirectoryPath: String
    public var rootDirectoryPath: String?
    public var runnerVersion: String?
    public var isImportedLocal: Bool
    public var serviceLabel: String
    public var currentJobName: String?
    public var currentRepo: String?
    public var lastHeartbeat: Date
    public var pid: Int32?

    @Relationship(deleteRule: .cascade, inverse: \JobRunEntity.runner)
    public var jobRuns: [JobRunEntity]

    public var status: RunnerStatus {
        get { RunnerStatus(rawValue: statusRaw) ?? .offline }
        set { statusRaw = newValue.rawValue }
    }

    public var scopeType: RunnerScopeType {
        get { RunnerScopeType(rawValue: scopeTypeRaw) ?? .repository }
        set { scopeTypeRaw = newValue.rawValue }
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
        pid: Int32? = nil
    ) {
        self.id = id
        self.name = name
        self.githubRunnerId = nil
        self.scopeTypeRaw = scopeType.rawValue
        self.scopeUrlString = scopeUrl.absoluteString
        self.statusRaw = status.rawValue
        self.labels = labels
        self.workDirectoryPath = workDirectory.path()
        self.rootDirectoryPath = rootDirectoryPath ?? workDirectory.deletingLastPathComponent().path()
        self.runnerVersion = runnerVersion
        self.isImportedLocal = isImportedLocal
        self.serviceLabel = "io.octorunner.agent.\(name)"
        self.currentJobName = nil
        self.currentRepo = nil
        self.lastHeartbeat = .now
        self.pid = pid
        self.jobRuns = []
    }
}
