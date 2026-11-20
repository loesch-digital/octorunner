import CoreModels
import Foundation
import SyncKit

public protocol RunnerProvisioning: Sendable {
    func provisionRunners(
        instanceNames: [String],
        scopeType: RunnerScopeType,
        scopeURL: URL,
        labels: [String],
        registerLaunchAgent: Bool,
        accessToken: String,
        configuration: RunnerLaunchConfiguration,
        runnerGroup: GitHubRunnerGroupDTO?,
        verifyAccountSelection: @escaping @MainActor @Sendable () throws -> Void,
        onStatusUpdate: @MainActor @Sendable (RunnerProvisioningProgress) -> Void
    ) async throws -> [ProvisionedRunnerSummary]
}

extension RunnerProvisionerActor: RunnerProvisioning {}
