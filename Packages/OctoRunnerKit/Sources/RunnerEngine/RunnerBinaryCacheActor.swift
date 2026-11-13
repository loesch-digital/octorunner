import CoreModels
import CryptoKit
import Foundation
import GitHubAPI

public enum RunnerEngineError: LocalizedError, Sendable {
    case sha256Mismatch(expected: String, actual: String)
    case downloadFailed(String)
    case extractionFailed(Int32)
    case configurationFailed(Int32, String)
    case launchAgentRegistrationFailed(Int32, String)
    case invalidRunnerName
    case runnerDirectoryAlreadyExists

    public var errorDescription: String? {
        switch self {
        case .sha256Mismatch(let expected, let actual):
            return "Runner binary SHA256 checksum mismatch (expected \(expected), got \(actual))."
        case .downloadFailed(let detail):
            return "Failed to download runner binary: \(detail)"
        case .extractionFailed(let code):
            return "Failed to extract runner archive (/usr/bin/tar exited with code \(code))."
        case .configurationFailed(let code, let log):
            return "config.sh exited with code \(code): \(log)"
        case .launchAgentRegistrationFailed(let code, let log):
            return "launchctl exited with code \(code): \(log)"
        case .invalidRunnerName:
            return "Runner names must be a single non-empty directory name without path separators or control characters."
        case .runnerDirectoryAlreadyExists:
            return "A managed runner directory already exists. Choose another name to preserve the existing runner."
        }
    }
}

public actor RunnerBinaryCacheActor {
    private let cacheDirectory: URL
    private let urlSession: URLSession
    private let checksumResolver: any GitHubRunnerChecksumResolving

    public init(
        cacheDirectory: URL? = nil,
        urlSession: URLSession = URLSession(configuration: .ephemeral),
        checksumResolver: any GitHubRunnerChecksumResolving = GitHubRunnerChecksumResolver()
    ) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Caches")
            self.cacheDirectory = caches.appending(path: "io.octorunner.macos/binaries", directoryHint: .isDirectory)
        }
        self.urlSession = urlSession
        self.checksumResolver = checksumResolver
    }

    public static func verifySHA256(of fileURL: URL, expectedHex: String) throws -> Bool {
        guard let expected = SHA256Checksum(expectedHex) else { return false }

        return try sha256(of: fileURL) == expected.hex
    }

    private static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try autoreleasepool { try handle.read(upToCount: 65_536) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public func ensureBinaryDownloadedAndVerified(
        package: GitHubRunnerDownloadDTO
    ) async throws -> URL {
        try Task.checkCancellation()
        let expected = try await checksumResolver.checksum(for: package)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let destinationURL = cacheDirectory.appending(path: package.filename)

        if FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)),
           let isValid = try? Self.verifySHA256(of: destinationURL, expectedHex: expected.hex),
           isValid {
            return destinationURL
        }

        try Task.checkCancellation()
        let tempURL: URL
        let response: URLResponse
        do { (tempURL, response) = try await urlSession.download(from: package.downloadUrl) }
        catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            // A redirected asset URL or transport diagnostic can contain temporary
            // credentials. Keep the displayed error independent of that content.
            throw RunnerEngineError.downloadFailed("The archive download failed. Try again later.")
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RunnerEngineError.downloadFailed("The archive server did not return a successful HTTP response.")
        }

        let actual = try Self.sha256(of: tempURL)
        guard actual == expected.hex else {
            throw RunnerEngineError.sha256Mismatch(expected: expected.hex, actual: actual)
        }

        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        return destinationURL
    }
}
