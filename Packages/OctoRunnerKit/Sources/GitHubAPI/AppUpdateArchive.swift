import Foundation
import Security

enum AppUpdateArchive {
    static func prepare(archive: URL, in staging: URL, replacing installed: URL, expectedVersion: String) async throws -> URL {
        let extractionDirectory = staging.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: false)
        do {
            let status = try await run("/usr/bin/ditto", arguments: ["-x", "-k", archive.path, extractionDirectory.path])
            guard status == 0 else { throw AppUpdateError.extractionFailed("ditto exited with code \(status)") }
            let candidate = extractionDirectory.appending(path: "OctoRunner.app", directoryHint: .isDirectory)
            try validateIdentity(candidate: candidate, installed: installed, expectedVersion: expectedVersion)
            try validateSignature(candidate: candidate, installed: installed)
            let assessment = try await run("/usr/sbin/spctl", arguments: ["--assess", "--type", "execute", candidate.path])
            guard assessment == 0 else { throw AppUpdateError.rejectedByGatekeeper }
            return candidate
        } catch {
            try? FileManager.default.removeItem(at: extractionDirectory)
            throw error
        }
    }

    static func validateIdentity(candidate: URL, installed: URL, expectedVersion: String) throws {
        guard isBundleDirectory(installed), isBundleDirectory(candidate),
              let existing = Bundle(url: installed), let replacement = Bundle(url: candidate),
              let identifier = existing.bundleIdentifier, identifier == replacement.bundleIdentifier,
              ReleaseVersion(expectedVersion) != nil,
              version(of: candidate) == expectedVersion,
              AppUpdaterActor.isVersion(expectedVersion, newerThan: version(of: installed))
        else { throw AppUpdateError.unexpectedBundle }
    }

    private static func isBundleDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        else { return false }
        return values.isDirectory == true && values.isSymbolicLink == false
    }

    static func validateSignature(candidate: URL, installed: URL) throws {
        let flags = SecCSFlags(rawValue: UInt32(kSecCSStrictValidate | kSecCSCheckNestedCode))
        var existingCode: SecStaticCode?
        var replacementCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(installed as CFURL, [], &existingCode) == errSecSuccess,
              let existingCode,
              SecStaticCodeCheckValidity(existingCode, flags, nil) == errSecSuccess,
              SecCodeCopyDesignatedRequirement(existingCode, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCreateWithPath(candidate as CFURL, [], &replacementCode) == errSecSuccess,
              let replacementCode,
              SecStaticCodeCheckValidity(replacementCode, flags, requirement) == errSecSuccess
        else { throw AppUpdateError.invalidSignature }
    }

    static func version(of bundle: URL) -> String {
        guard let data = try? Data(contentsOf: bundle.appending(path: "Contents/Info.plist")),
              let metadata = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
        else { return "0.0.0" }
        return AppUpdaterActor.bundleReleaseVersion(
            shortVersion: metadata["CFBundleShortVersionString"] as? String,
            releaseVersion: metadata["OctoRunnerReleaseVersion"] as? String)
    }

    private static func run(_ executable: String, arguments: [String]) async throws -> Int32 {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus) }
            do { try process.run() }
            catch { continuation.resume(throwing: error) }
        }
        try Task.checkCancellation()
        return status
    }
}
