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
        }
    }
}

public actor RunnerBinaryCacheActor {
    private let cacheDirectory: URL
    private let urlSession: URLSession

    public init(
        cacheDirectory: URL? = nil,
        urlSession: URLSession = .shared
    ) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Caches")
            self.cacheDirectory = caches.appending(path: "io.octorunner.macos/binaries", directoryHint: .isDirectory)
        }
        self.urlSession = urlSession
    }

    public static func verifySHA256(of fileURL: URL, expectedHex: String) throws -> Bool {
        let cleanExpected = expectedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanExpected.isEmpty else { return true }

        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        let actualHex = digest.map { String(format: "%02x", $0) }.joined()
        return actualHex == cleanExpected
    }

    public func ensureBinaryDownloadedAndVerified(
        package: GitHubRunnerDownloadDTO
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let destinationURL = cacheDirectory.appending(path: package.filename)

        if FileManager.default.fileExists(atPath: destinationURL.path()),
           let isValid = try? Self.verifySHA256(of: destinationURL, expectedHex: package.sha256Checksum ?? ""),
           isValid {
            return destinationURL
        }

        let (tempURL, response) = try await urlSession.download(from: package.downloadUrl)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RunnerEngineError.downloadFailed("HTTP error downloading \(package.downloadUrl.absoluteString)")
        }

        if let expected = package.sha256Checksum, !expected.isEmpty {
            let valid = try Self.verifySHA256(of: tempURL, expectedHex: expected)
            if !valid {
                let data = try Data(contentsOf: tempURL, options: .mappedIfSafe)
                let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                try? FileManager.default.removeItem(at: tempURL)
                throw RunnerEngineError.sha256Mismatch(expected: expected, actual: actual)
            }
        }

        if FileManager.default.fileExists(atPath: destinationURL.path()) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        return destinationURL
    }
}
