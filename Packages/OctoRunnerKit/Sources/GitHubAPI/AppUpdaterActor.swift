import Foundation

public struct GitHubReleaseAssetDTO: Codable, Sendable, Equatable {
    public let name: String
    public let browserDownloadUrl: URL
    public let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

public struct GitHubReleaseDTO: Codable, Sendable, Equatable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: URL
    public let publishedAt: String?
    public let assets: [GitHubReleaseAssetDTO]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

public struct AppUpdateInfo: Sendable, Equatable {
    public let currentVersion: String
    public let latestVersion: String
    public let releaseTitle: String
    public let releaseNotes: String
    public let releasePageURL: URL
    public let zipDownloadURL: URL?
    public let isUpdateAvailable: Bool

    public init(
        currentVersion: String,
        latestVersion: String,
        releaseTitle: String,
        releaseNotes: String,
        releasePageURL: URL,
        zipDownloadURL: URL?,
        isUpdateAvailable: Bool
    ) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.releaseTitle = releaseTitle
        self.releaseNotes = releaseNotes
        self.releasePageURL = releasePageURL
        self.zipDownloadURL = zipDownloadURL
        self.isUpdateAvailable = isUpdateAvailable
    }
}

public enum AppUpdateError: LocalizedError, Sendable, Equatable {
    case invalidReleaseResponse
    case missingDownloadAsset
    case extractionFailed(String)
    case unexpectedBundle
    case invalidSignature
    case rejectedByGatekeeper
    case couldNotReplace
    case couldNotRestore
    case couldNotStart
    case manualRecoveryRequired

    public var errorDescription: String? {
        switch self {
        case .invalidReleaseResponse:
            return "Could not query latest release from GitHub."
        case .missingDownloadAsset:
            return "No macOS arm64 release archive found in the latest GitHub Release."
        case .extractionFailed(let detail):
            return "Failed to unpack update archive: \(detail)"
        case .unexpectedBundle:
            return "The archive does not contain the expected OctoRunner release."
        case .invalidSignature:
            return "The update signature does not match the installed app."
        case .rejectedByGatekeeper:
            return "macOS did not accept the downloaded update."
        case .couldNotReplace:
            return "The installed app could not be replaced."
        case .couldNotRestore:
            return "The previous app could not be restored automatically."
        case .couldNotStart:
            return "The updated app did not finish starting."
        case .manualRecoveryRequired:
            return "The update requires manual recovery. The previous installation has been kept."
        }
    }
}

public actor AppUpdaterActor {
    private let repositoryOwner: String
    private let repositoryName: String
    private let urlSession: URLSession

    public init(
        repositoryOwner: String = "loesch-digital",
        repositoryName: String = "octorunner",
        urlSession: URLSession = .shared
    ) {
        self.repositoryOwner = repositoryOwner
        self.repositoryName = repositoryName
        self.urlSession = urlSession
    }

    public static var currentBundleVersion: String {
        bundleReleaseVersion(
            shortVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            releaseVersion: Bundle.main.infoDictionary?["OctoRunnerReleaseVersion"] as? String
        )
    }

    static func bundleReleaseVersion(shortVersion: String?, releaseVersion: String?) -> String {
        if let releaseVersion, ReleaseVersion(releaseVersion) != nil { return releaseVersion }
        if let shortVersion, ReleaseVersion(shortVersion) != nil { return shortVersion }
        return "0.0.0"
    }

    /// Returns `true` if `candidate` is strictly newer than `current` (e.g. "0.3.0" > "0.2.1").
    public static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func parse(_ raw: String) -> ReleaseVersion? {
            var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
            return ReleaseVersion(value)
        }
        guard let candidate = parse(candidate), let current = parse(current) else { return false }
        return candidate > current
    }

    public func checkForUpdates(currentVersion: String = AppUpdaterActor.currentBundleVersion) async throws -> AppUpdateInfo {
        let url = URL(string: "https://api.github.com/repos/\(repositoryOwner)/\(repositoryName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppUpdateError.invalidReleaseResponse
        }

        let release = try JSONDecoder().decode(GitHubReleaseDTO.self, from: data)
        let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let zipAsset = release.assets.first { $0.name.hasSuffix("-arm64.zip") || $0.name.hasSuffix(".zip") }
        let newer = Self.isVersion(latestVersion, newerThan: currentVersion)

        return AppUpdateInfo(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releaseTitle: release.name ?? release.tagName,
            releaseNotes: release.body ?? "",
            releasePageURL: release.htmlUrl,
            zipDownloadURL: zipAsset?.browserDownloadUrl,
            isUpdateAvailable: newer
        )
    }

    /// Validates the archive in a private directory on the installed app's volume.
    public func downloadAndStageUpdate(
        from zipURL: URL, expectedVersion: String, targetAppURL: URL = Bundle.main.bundleURL
    ) async throws -> StagedAppUpdate {
        let installed = targetAppURL.resolvingSymlinksInPath()
        guard FileManager.default.isWritableFile(atPath: installed.deletingLastPathComponent().path) else {
            throw AppUpdateError.couldNotReplace
        }
        let (tempZipURL, response) = try await urlSession.download(from: zipURL)
        defer { try? FileManager.default.removeItem(at: tempZipURL) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppUpdateError.invalidReleaseResponse
        }

        let stagingDir = try StagedAppUpdate.makeStagingDirectory(beside: installed)
        do {
            let candidate = try await AppUpdateArchive.prepare(
                archive: tempZipURL, in: stagingDir, replacing: installed, expectedVersion: expectedVersion)
            return StagedAppUpdate(directory: stagingDir, candidate: candidate, installed: installed, version: expectedVersion)
        } catch {
            try? FileManager.default.removeItem(at: stagingDir)
            throw error
        }
    }
}
