import CoreModels

public protocol GitHubRunnerChecksumResolving: Sendable {
    func checksum(for package: GitHubRunnerDownloadDTO) async throws -> SHA256Checksum
}
