import CoreModels
import Foundation

public protocol RunnerProvisioning: Sendable {
    func provisionRunners(
        instanceNames: [String],
        scopeType: RunnerScopeType,
        scopeURL: URL,
        labels: [String],
        registerLaunchAgent: Bool,
        accessToken: String,
        configuration: RunnerLaunchConfiguration,
        onStatusUpdate: @MainActor @Sendable (String) -> Void
    ) async throws -> [ProvisionedRunnerSummary]
}

extension RunnerProvisionerActor: RunnerProvisioning {}
