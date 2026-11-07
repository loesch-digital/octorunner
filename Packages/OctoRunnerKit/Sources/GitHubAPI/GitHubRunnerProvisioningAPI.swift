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
    case invalidScopeURL(String)
    case httpError(Int, String)
    case noArm64RunnerPackageFound

    public var errorDescription: String? {
        switch self {
        case .missingAuthToken:
            return "No active GitHub authentication token found in Keychain."
        case .invalidScopeURL(let url):
            return "Invalid GitHub scope URL: \(url)"
        case .httpError(let status, let detail):
            return "GitHub API returned HTTP \(status): \(detail)"
        case .noArm64RunnerPackageFound:
            return "GitHub API returned no osx-arm64 runner download package."
        }
    }
}

public actor GitHubRunnerProvisioningClient {
    private let keychain: KeychainVaultActor
    private let urlSession: URLSession

    public init(
        keychain: KeychainVaultActor = KeychainVaultActor(),
        urlSession: URLSession = .shared
    ) {
        self.keychain = keychain
        self.urlSession = urlSession
    }

    public func readToken(for accountLogin: String) async throws -> String {
        guard let token = try await keychain.readSecret(account: accountLogin), !token.isEmpty else {
            throw GitHubProvisioningError.missingAuthToken
        }
        return token
    }

    public func fetchUserRepositories(token: String) async throws -> [GitHubRepositorySummaryDTO] {
        let url = URL(string: "https://api.github.com/user/repos?affiliation=owner,collaborator,organization_member&sort=updated&per_page=100")!
        let data = try await performGET(url: url, token: token)
        return try JSONDecoder().decode([GitHubRepositorySummaryDTO].self, from: data)
    }

    public func fetchUserOrganizations(token: String) async throws -> [GitHubOrganizationSummaryDTO] {
        let url = URL(string: "https://api.github.com/user/orgs?per_page=100")!
        let data = try await performGET(url: url, token: token)
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

        let data = try await performGET(url: endpointURL, token: token)
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

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubProvisioningError.httpError(0, "Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubProvisioningError.httpError(http.statusCode, body)
        }
        return try JSONDecoder().decode(GitHubRegistrationTokenDTO.self, from: data)
    }

    public static func parseOwnerAndRepo(from scopeURL: URL) throws -> (owner: String, repo: String?) {
        let parts = scopeURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let owner = parts.first else {
            throw GitHubProvisioningError.invalidScopeURL(scopeURL.absoluteString)
        }
        let repo = parts.count >= 2 ? parts[1] : nil
        return (owner, repo)
    }

    private func performGET(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubProvisioningError.httpError(0, "Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubProvisioningError.httpError(http.statusCode, body)
        }
        return data
    }
}
