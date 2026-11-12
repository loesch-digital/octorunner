import CoreModels
import Foundation

/// Resolves missing runner-download checksums from public release metadata.
/// No account credential, cookies or additional OAuth scopes are required.
public actor GitHubRunnerChecksumResolver: GitHubRunnerChecksumResolving {
    private let transport: any GitHubActionsTransport
    private var cached: [String: SHA256Checksum] = [:]

    public init(transport: any GitHubActionsTransport = GitHubActionsURLSessionTransport()) {
        self.transport = transport
    }

    public func checksum(for package: GitHubRunnerDownloadDTO) async throws -> SHA256Checksum {
        try Task.checkCancellation()
        let version = try Self.validateIdentity(package)
        if let raw = package.sha256Checksum, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let checksum = SHA256Checksum(raw) else { throw GitHubRunnerChecksumError.invalidMetadata }
            return checksum
        }
        if let checksum = cached[package.filename] { return checksum }
        guard let url = URL(string: "https://api.github.com/repos/actions/runner/releases/tags/v\(version)") else {
            throw GitHubRunnerChecksumError.invalidMetadata
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        let response: GitHubActionsHTTPResponse
        do { response = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw GitHubRunnerChecksumError.unavailable }
        try Task.checkCancellation()
        guard response.statusCode == 200 else { throw GitHubRunnerChecksumError.unavailable }
        guard let release = try? JSONDecoder().decode(Release.self, from: response.data),
              release.tagName == "v\(version)", !release.draft, !release.prerelease else {
            throw GitHubRunnerChecksumError.checksumUnavailable
        }
        let matches = release.assets.filter {
            $0.name == package.filename && $0.browserDownloadURL == package.downloadUrl.absoluteString && $0.state == "uploaded"
        }
        guard matches.count == 1, let digest = matches.first?.digest, digest.hasPrefix("sha256:"),
              let checksum = SHA256Checksum(String(digest.dropFirst(7))) else {
            throw GitHubRunnerChecksumError.checksumUnavailable
        }
        if cached.count >= 64, let victim = cached.keys.first { cached.removeValue(forKey: victim) }
        cached[package.filename] = checksum
        return checksum
    }

    private static func validateIdentity(_ package: GitHubRunnerDownloadDTO) throws -> String {
        let prefix = "actions-runner-osx-arm64-"
        let suffix = ".tar.gz"
        guard package.os == "osx", package.architecture == "arm64", package.filename.hasPrefix(prefix),
              package.filename.hasSuffix(suffix), package.filename.utf8.count <= 100 else {
            throw GitHubRunnerChecksumError.invalidMetadata
        }
        let version = String(package.filename.dropFirst(prefix.count).dropLast(suffix.count))
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              package.downloadUrl.absoluteString == "https://github.com/actions/runner/releases/download/v\(version)/\(package.filename)" else {
            throw GitHubRunnerChecksumError.invalidMetadata
        }
        return version
    }

    private struct Release: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease, assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String
        let state: String
        let digest: String?
        enum CodingKeys: String, CodingKey {
            case name, state, digest
            case browserDownloadURL = "browser_download_url"
        }
    }
}
