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
