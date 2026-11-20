import Darwin
import Foundation
import SyncKit

public struct RunnerMigrationRecovery: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, Sendable {
        case preparing, registering, registered, starting, committing
    }

    public let runnerID: UUID
    public let oldRemoteID: Int64
    public let newRemoteID: Int64?
    public let source: URL
    public let destination: URL
    public let stage: Stage
    public let launchAgent: Bool?
    public let version: String?
    let artifact: Artifact?

    init(runnerID: UUID, oldRemoteID: Int64, newRemoteID: Int64?, source: URL, destination: URL,
         stage: Stage, artifact: Artifact? = nil, launchAgent: Bool? = nil, version: String? = nil) {
        self.runnerID = runnerID
        self.oldRemoteID = oldRemoteID
        self.newRemoteID = newRemoteID
        self.source = source
        self.destination = destination
        self.stage = stage
        self.artifact = artifact
        self.launchAgent = launchAgent
        self.version = version
    }

    func at(_ stage: Stage, newRemoteID: Int64? = nil, artifact: Artifact? = nil, version: String? = nil) -> Self {
        Self(runnerID: runnerID, oldRemoteID: oldRemoteID, newRemoteID: newRemoteID ?? self.newRemoteID,
             source: source, destination: destination, stage: stage, artifact: artifact ?? self.artifact,
             launchAgent: launchAgent, version: version ?? self.version)
    }

    struct Artifact: Codable, Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
        let birthSeconds: Int
        let birthNanoseconds: Int

        static func read(at directory: URL) throws -> Self? {
            var info = stat()
            guard lstat(directory.path, &info) == 0 else {
                if errno == ENOENT { return nil }
                throw RunnerMigrationError.recoveryRequired
            }
            guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(),
                  info.st_mode & (S_IWGRP | S_IWOTH) == 0 else { throw RunnerMigrationError.recoveryRequired }
            return Self(device: info.st_dev, inode: info.st_ino,
                        birthSeconds: info.st_birthtimespec.tv_sec, birthNanoseconds: info.st_birthtimespec.tv_nsec)
        }
    }
}

/// The one small journal per model identity records the last attempted stage
/// before a side effect. A staged file and atomic link prevent competing starts.
struct RunnerMigrationJournal: Sendable {
    let directory: URL

    func begin(_ entry: RunnerMigrationRecovery) throws {
        let fileManager = FileManager.default
        try createDirectory()
        let staged = directory.appending(path: UUID().uuidString + ".tmp")
        defer { try? fileManager.removeItem(at: staged) }
        try JSONEncoder().encode(entry).write(to: staged, options: .withoutOverwriting)
        guard link(staged.path, file(for: entry.runnerID).path) == 0 else {
            if errno == EEXIST { throw RunnerMigrationError.recoveryRequired }
            throw Self.systemError()
        }
    }

    /// The kernel releases the lock if OctoRunner exits before completing a step.
    func lock() throws -> Int32 {
        try createDirectory()
        let file = directory.appending(path: ".operation")
        let descriptor = open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Self.systemError() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid() else {
            close(descriptor)
            throw RunnerMigrationError.recoveryRequired
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw RunnerSupervisionError.operationInProgress
        }
        return descriptor
    }

    func pending(_ runnerID: UUID) throws -> RunnerMigrationRecovery? {
        guard try directoryExists() else { return nil }
        let descriptor = open(file(for: runnerID).path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw RunnerMigrationError.recoveryRequired
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        let maximumBytes = 32 * 1024
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              (1...Int64(maximumBytes)).contains(info.st_size),
              let data = try handle.read(upToCount: maximumBytes + 1), data.count == info.st_size,
              let entry = try? JSONDecoder().decode(RunnerMigrationRecovery.self, from: data),
              entry.runnerID == runnerID, entry.source.isFileURL, entry.destination.isFileURL,
              entry.oldRemoteID > 0, entry.newRemoteID.map({ $0 > 0 }) ?? true else {
            throw RunnerMigrationError.recoveryRequired
        }
        return entry
    }

    func update(_ entry: RunnerMigrationRecovery) throws {
        guard try pending(entry.runnerID) != nil else { throw RunnerMigrationError.recoveryRequired }
        try JSONEncoder().encode(entry).write(to: file(for: entry.runnerID), options: .atomic)
    }

    func complete(_ runnerID: UUID) throws {
        guard try pending(runnerID) != nil else { return }
        guard unlink(file(for: runnerID).path) == 0 else { throw Self.systemError() }
    }

    func protectedPaths() throws -> Set<String> {
        guard try directoryExists() else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let runnerIDs = files.compactMap { file -> UUID? in
            guard file.pathExtension == "json" else { return nil }
            return UUID(uuidString: file.deletingPathExtension().lastPathComponent)
        }
        var paths: Set<String> = []
        for id in runnerIDs {
            guard let entry = try pending(id) else { continue }
            paths.insert(LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: entry.source))
            paths.insert(LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: entry.destination))
        }
        return paths
    }

    private func file(for runnerID: UUID) -> URL {
        directory.appending(path: runnerID.uuidString + ".json")
    }

    private func createDirectory() throws {
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        if mkdir(directory.path, 0o700) == -1, errno != EEXIST { throw Self.systemError() }
        guard try directoryExists() else { throw RunnerMigrationError.recoveryRequired }
    }

    private func directoryExists() throws -> Bool {
        var info = stat()
        guard lstat(directory.path, &info) == 0 else {
            if errno == ENOENT { return false }
            throw Self.systemError()
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            throw RunnerMigrationError.recoveryRequired
        }
        return true
    }

    private static func systemError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
