import CoreModels
import Foundation
import SecurityKit

public struct GitHubRepositorySummaryDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let name: String
    public let fullName: String
    public let htmlUrl: URL
    public let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case htmlUrl = "html_url"
        case isPrivate = "private"
    }

    public var ownerLogin: String {
        String(fullName.split(separator: "/").first ?? "")
    }
}

public struct GitHubOrganizationSummaryDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let login: String
    public let description: String?
    public let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case description
        case avatarUrl = "avatar_url"
    }

    public var htmlUrl: URL {
        URL(string: "https://github.com/\(login)")!
    }
}

public struct GitHubRegistrationTokenDTO: Codable, Sendable, Equatable {
    public let token: String
    public let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
    }
}

public enum GitHubProvisioningError: LocalizedError, Sendable {
    case missingAuthToken
    case invalidScopeURL
    case httpError(Int, String)
    case noArm64RunnerPackageFound

    public var errorDescription: String? {
        switch self {
        case .missingAuthToken:
            return "No active GitHub authentication token found in Keychain."
        case .invalidScopeURL:
            return "Invalid GitHub runner scope URL."
        case .httpError(let status, let detail):
            return "GitHub API returned HTTP \(status): \(detail)"
        case .noArm64RunnerPackageFound:
            return "GitHub API returned no osx-arm64 runner download package."
        }
    }
}

public actor GitHubRunnerProvisioningClient {
    private let keychain: KeychainVaultActor
    private let transport: any GitHubActionsTransport

    public init(
        keychain: KeychainVaultActor = KeychainVaultActor(),
        transport: any GitHubActionsTransport = GitHubActionsURLSessionTransport()
    ) {
        self.keychain = keychain
        self.transport = transport
    }

    public init(keychain: KeychainVaultActor = KeychainVaultActor(), urlSession: URLSession) {
        self.init(keychain: keychain, transport: GitHubActionsURLSessionTransport(session: urlSession))
    }

    public func readToken(for accountLogin: String) async throws -> String {
        guard let token = try await keychain.readSecret(account: accountLogin), !token.isEmpty else {
            throw GitHubProvisioningError.missingAuthToken
        }
        return token
    }

    public func fetchUserRepositories(token: String) async throws -> [GitHubRepositorySummaryDTO] {
        let url = URL(string: "https://api.github.com/user/repos?affiliation=owner,collaborator,organization_member&sort=updated&per_page=100")!
        let data = try await sendRequest(url: url, token: token, method: "GET")
        return try JSONDecoder().decode([GitHubRepositorySummaryDTO].self, from: data)
    }

    public func fetchUserOrganizations(token: String) async throws -> [GitHubOrganizationSummaryDTO] {
        let url = URL(string: "https://api.github.com/user/orgs?per_page=100")!
        let data = try await sendRequest(url: url, token: token, method: "GET")
        return try JSONDecoder().decode([GitHubOrganizationSummaryDTO].self, from: data)
    }

    public func fetchArm64RunnerDownload(
        scopeURL: URL,
        token: String
    ) async throws -> GitHubRunnerDownloadDTO {
        let (owner, repo) = try Self.parseOwnerAndRepo(from: scopeURL)
        let endpointURL: URL
        if let repo {
            endpointURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/actions/runners/downloads")!
        } else {
            endpointURL = URL(string: "https://api.github.com/orgs/\(owner)/actions/runners/downloads")!
        }

        let data = try await sendRequest(url: endpointURL, token: token, method: "GET")
        let packages = try JSONDecoder().decode([GitHubRunnerDownloadDTO].self, from: data)
        guard let match = packages.first(where: { $0.os == "osx" && $0.architecture == "arm64" }) else {
            throw GitHubProvisioningError.noArm64RunnerPackageFound
        }
        return match
    }

    public func createRegistrationToken(
        scopeURL: URL,
        token: String
    ) async throws -> GitHubRegistrationTokenDTO {
        let (owner, repo) = try Self.parseOwnerAndRepo(from: scopeURL)
        let endpointURL: URL
        if let repo {
            endpointURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/actions/runners/registration-token")!
        } else {
            endpointURL = URL(string: "https://api.github.com/orgs/\(owner)/actions/runners/registration-token")!
        }

        let data = try await sendRequest(url: endpointURL, token: token, method: "POST")
        return try JSONDecoder().decode(GitHubRegistrationTokenDTO.self, from: data)
    }

    public func replaceRunnerLabels(
        scopeURL: URL,
        runnerId: Int64,
        labels: [String],
        token: String
    ) async throws -> [String] {
        let (owner, repo) = try Self.parseOwnerAndRepo(from: scopeURL)
        let endpointURL: URL
        if let repo {
            endpointURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/actions/runners/\(runnerId)/labels")!
        } else {
            endpointURL = URL(string: "https://api.github.com/orgs/\(owner)/actions/runners/\(runnerId)/labels")!
        }

        let body = try JSONSerialization.data(withJSONObject: ["labels": labels])
        let data = try await sendRequest(url: endpointURL, token: token, method: "PUT", body: body)
        let response = try JSONDecoder().decode(LabelResponse.self, from: data)
        return response.labels.map(\.name)
    }

    private struct LabelResponse: Decodable {
        struct Label: Decodable {
            let name: String
        }

        let labels: [Label]
    }

    public static func isValidScope(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", components.host?.lowercased() == "github.com",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil else { return false }
        let path = components.percentEncodedPath
        guard path.hasPrefix("/") else { return false }
        var segments = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        if segments.last == "" { segments.removeLast() }
        guard (1...2).contains(segments.count),
              segments[0].wholeMatch(of: /[a-zA-Z0-9][a-zA-Z0-9-]*/) != nil else { return false }
        return segments.count == 1 || (
            segments[1] != "." && segments[1] != ".."
                && segments[1].wholeMatch(of: /[a-zA-Z0-9_.-]+/) != nil
        )
    }

    public static func parseOwnerAndRepo(from scopeURL: URL) throws -> (owner: String, repo: String?) {
        guard isValidScope(scopeURL) else { throw GitHubProvisioningError.invalidScopeURL }
        let parts = scopeURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        return (parts[0], parts.count == 2 ? parts[1] : nil)
    }

    private func sendRequest(url: URL, token: String, method: String, body: Data? = nil) async throws -> Data {
        try Task.checkCancellation()
        guard !token.isEmpty, token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw GitHubProvisioningError.missingAuthToken
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let response = try await transport.send(request)
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubProvisioningError.httpError(response.statusCode, "Runner API request failed.")
        }
        return response.data
    }
}
