import Darwin
import Foundation

final class AppUpdateStoreLease {
    private let descriptor: Int32

    init?(lock: URL, exclusive: Bool) throws {
        let file = open(lock.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard file >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        guard flock(file, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0 else {
            let reason = errno
            close(file)
            if reason == EWOULDBLOCK { return nil }
            throw CocoaError(.fileWriteUnknown)
        }
        descriptor = file
    }

    deinit { close(descriptor) }

    static func authorizeCandidate(installerLock: URL, candidateLock: URL) throws -> AppUpdateStoreLease? {
        guard let candidate = try AppUpdateStoreLease(lock: candidateLock, exclusive: true),
              try AppUpdateStoreLease(lock: installerLock, exclusive: false) == nil
        else { return nil }
        return candidate
    }
}

struct AppUpdateStoreBackup: Codable, Sendable {
    private static let suffixes = ["", "-wal", "-shm", "-journal"]
    private static let backupPrefix = ".octorunner-store-backup-"
    private let store: URL
    private let directory: URL
    private let savedSuffixes: [String]

    init(store: URL) throws {
        let files = FileManager.default
        self.store = store.deletingLastPathComponent().resolvingSymlinksInPath().appending(path: store.lastPathComponent)
        let backupDirectory = self.store.deletingLastPathComponent().appending(
            path: Self.backupPrefix + UUID().uuidString, directoryHint: .isDirectory)
        directory = backupDirectory
        try files.createDirectory(at: backupDirectory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        do {
            savedSuffixes = try Self.suffixes.filter { suffix in
                let original = URL(filePath: store.path + suffix)
                guard files.fileExists(atPath: original.path) else { return false }
                let values = try original.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink == false else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try files.copyItem(at: original, to: backupDirectory.appending(path: "Store" + suffix))
                return true
            }
        } catch {
            try? files.removeItem(at: backupDirectory)
            throw error
        }
    }

    func hasExpectedLayout(for storeURL: URL) -> Bool {
        let parent = storeURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let name = directory.lastPathComponent
        guard store.path == parent.appending(path: storeURL.lastPathComponent).path,
              directory.deletingLastPathComponent().path == parent.path,
              directory.resolvingSymlinksInPath().path == directory.path,
              name.hasPrefix(Self.backupPrefix),
              UUID(uuidString: String(name.dropFirst(Self.backupPrefix.count))) != nil,
              let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              attributes[.ownerAccountID] as? UInt32 == geteuid(),
              attributes[.posixPermissions] as? Int == 0o700
        else { return false }
        return true
    }

    /// Restoring archive files is repeatable while the store lease is held.
    /// The source is retained even if a write fails midway through recovery.
    func restore() throws {
        let files = FileManager.default
        let location = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard location.isDirectory == true, location.isSymbolicLink == false,
              savedSuffixes.allSatisfy(Self.suffixes.contains)
        else { throw CocoaError(.fileReadCorruptFile) }
        let staging = directory.appending(path: "Restore-\(UUID())", directoryHint: .isDirectory)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }
        // Verify and stage every file before modifying the current store.
        for suffix in savedSuffixes {
            let backup = snapshot(suffix)
            let values = try backup.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink == false else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try files.copyItem(at: backup, to: staging.appending(path: backup.lastPathComponent))
        }
        for suffix in Self.suffixes {
            let destination = URL(filePath: store.path + suffix)
            if savedSuffixes.contains(suffix) {
                let copy = staging.appending(path: snapshot(suffix).lastPathComponent)
                guard rename(copy.path, destination.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            } else if files.fileExists(atPath: destination.path) {
                try files.removeItem(at: destination)
            }
        }
    }

    private func snapshot(_ suffix: String) -> URL {
        directory.appending(path: "Store" + suffix)
    }

    func discard() {
        try? FileManager.default.removeItem(at: directory)
    }
}

struct AppUpdateJournal: Codable, Sendable {
    let update: StagedAppUpdate
    let previousVersion: String
    let store: AppUpdateStoreBackup

    static let directory = URL.applicationSupportDirectory.appending(path: "io.octorunner.macos-update", directoryHint: .isDirectory)
    static let file = directory.appending(path: "pending.json")
    static let lock = directory.appending(path: "store.lock")
    static let installerLock = directory.appending(path: "installer.lock")
    static let candidateLock = directory.appending(path: "candidate.lock")

    static func lease(exclusive: Bool) throws -> AppUpdateStoreLease? {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return try AppUpdateStoreLease(lock: lock, exclusive: exclusive)
    }

    func save() throws {
        try JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
    }

    func finish() throws {
        try FileManager.default.removeItem(at: Self.file)
        store.discard()
        update.discard()
    }

    func rollback() throws {
        let installed = AppUpdateArchive.version(of: update.installed)
        if installed == update.version {
            guard AppUpdateArchive.version(of: update.candidate) == previousVersion
            else { throw AppUpdateError.couldNotRestore }
            try store.restore()
            guard AppUpdateBundleSwap.swap(update.candidate, update.installed) else {
                throw AppUpdateError.couldNotRestore
            }
        } else if installed != previousVersion {
            throw AppUpdateError.couldNotRestore
        }
    }
}
