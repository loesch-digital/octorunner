import CoreModels
import Foundation

public struct GitHubRunnerDownloadDTO: Codable, Sendable, Equatable {
    public let os: String
    public let architecture: String
    public let downloadUrl: URL
    public let filename: String
    public let sha256Checksum: String?

    enum CodingKeys: String, CodingKey {
        case os
        case architecture
        case downloadUrl = "download_url"
        case filename
        case sha256Checksum = "sha256_checksum"
    }

    public init(
        os: String,
        architecture: String,
        downloadUrl: URL,
        filename: String,
        sha256Checksum: String? = nil
    ) {
        self.os = os
        self.architecture = architecture
        self.downloadUrl = downloadUrl
        self.filename = filename
        self.sha256Checksum = sha256Checksum
    }
}

public actor GitHubAPIClientActor {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func pingGitHubAPI() async -> Bool {
        guard let url = URL(string: "https://api.github.com/zen") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
