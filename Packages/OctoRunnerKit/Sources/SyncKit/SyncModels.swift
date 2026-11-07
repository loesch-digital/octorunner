import CoreModels
import Foundation

public struct LocalDotRunnerConfig: Codable, Sendable, Equatable {
    public let agentId: Int64
    public let agentName: String
    public let poolId: Int?
    public let poolName: String?
    public let serverUrl: String?
    public let gitHubUrl: URL
    public let workFolder: String

    public init(
        agentId: Int64,
        agentName: String,
        poolId: Int? = 1,
        poolName: String? = "Default",
        serverUrl: String? = nil,
        gitHubUrl: URL,
        workFolder: String = "_work"
    ) {
        self.agentId = agentId
        self.agentName = agentName
        self.poolId = poolId
        self.poolName = poolName
        self.serverUrl = serverUrl
        self.gitHubUrl = gitHubUrl
        self.workFolder = workFolder
    }

    /// Strips the .NET UTF-8 Byte Order Mark (`0xEF 0xBB 0xBF`) if present before decoding `.runner` JSON.
    public static func decode(from rawData: Data) throws -> LocalDotRunnerConfig {
        let utf8BOM = Data([0xEF, 0xBB, 0xBF])
        let cleanData: Data
        if rawData.starts(with: utf8BOM) {
            cleanData = Data(rawData.dropFirst(utf8BOM.count))
        } else {
            cleanData = rawData
        }
        return try JSONDecoder().decode(LocalDotRunnerConfig.self, from: cleanData)
    }

    public var inferredScopeType: RunnerScopeType {
        let components = gitHubUrl.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        return components.count >= 2 ? .repository : .organization
    }

    public var ownerAndRepo: (owner: String, repo: String?)? {
        let components = gitHubUrl.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let owner = components.first else { return nil }
        let repo = components.count >= 2 ? components[1] : nil
        return (owner, repo)
    }
}

public struct LocalRunnerProcessState: Sendable, Equatable {
    public let listenerPID: Int32
    public var isWorkerActive: Bool

    public init(listenerPID: Int32, isWorkerActive: Bool = false) {
        self.listenerPID = listenerPID
        self.isWorkerActive = isWorkerActive
    }
}

public struct DiscoveredLocalRunner: Sendable, Equatable, Identifiable {
    public var id: String { rootDirectory.standardizedFileURL.path() }
    public let rootDirectory: URL
    public let config: LocalDotRunnerConfig
    public let workDirectory: URL
    public let runnerVersion: String?
    public let listenerPID: Int32?
    public let isWorkerActive: Bool
    public var labels: [String]
    public var localStatus: RunnerStatus

    public init(
        rootDirectory: URL,
        config: LocalDotRunnerConfig,
        workDirectory: URL,
        runnerVersion: String?,
        listenerPID: Int32?,
        isWorkerActive: Bool,
        labels: [String] = ["self-hosted", "macos", "arm64"]
    ) {
        self.rootDirectory = rootDirectory
        self.config = config
        self.workDirectory = workDirectory
        self.runnerVersion = runnerVersion
        self.listenerPID = listenerPID
        self.isWorkerActive = isWorkerActive
        self.labels = labels
        if isWorkerActive {
            self.localStatus = .busy
        } else if listenerPID != nil {
            self.localStatus = .idle
        } else {
            self.localStatus = .offline
        }
    }
}

public struct GitHubRunnerLabelDTO: Codable, Sendable, Equatable {
    public let id: Int64?
    public let name: String
    public let type: String?
}

public struct GitHubRemoteRunnerDTO: Codable, Sendable, Equatable {
    public let id: Int64
    public let name: String
    public let os: String
    public let status: String
    public let busy: Bool
    public let labels: [GitHubRunnerLabelDTO]

    public var labelNames: [String] {
        labels.map(\.name)
    }
}
