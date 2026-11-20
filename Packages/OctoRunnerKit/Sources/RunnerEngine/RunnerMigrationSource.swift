import Darwin
import Foundation
import SyncKit

public enum RunnerMigrationError: Error, Sendable, Equatable {
    case unverifiedSource
    case sourceChanged
    case runnerIdentityMismatch
    case runnerNotAccessible
    case runnerBusy
    case listenerStillRunning
    case labelsChanged
    case incompatibleRunnerLabels
    case groupChanged
    case recoveryRequired
    case conflictingService
    case sourceServiceInstalled
    case unsupportedSourcePolicy
}

/// Identifies the chosen runner by its directory, metadata file and decoded configuration.
/// All paths inside the selected directory other than .runner are left untouched.
struct RunnerMigrationSource: Equatable, Sendable {
    let rootDirectory: URL
    let configuration: LocalDotRunnerConfig
    private let directoryIdentity: FileIdentity
    private let configurationIdentity: FileIdentity

    static func inspect(_ selectedDirectory: URL) throws -> Self {
        try Task.checkCancellation()
        guard selectedDirectory.isFileURL else { throw RunnerMigrationError.unverifiedSource }
        let root = selectedDirectory.standardizedFileURL
        let directoryDescriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryDescriptor >= 0 else { throw RunnerMigrationError.unverifiedSource }
        defer { close(directoryDescriptor) }
        let directory = try attributes(of: directoryDescriptor, type: S_IFDIR)
        var service = stat()
        guard fstatat(directoryDescriptor, ".service", &service, AT_SYMLINK_NOFOLLOW) != 0 else {
            throw RunnerMigrationError.sourceServiceInstalled
        }
        guard errno == ENOENT else { throw RunnerMigrationError.unverifiedSource }

        let metadataDescriptor = openat(directoryDescriptor, ".runner", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard metadataDescriptor >= 0 else { throw RunnerMigrationError.unverifiedSource }
        let metadata = FileHandle(fileDescriptor: metadataDescriptor, closeOnDealloc: true)
        defer { try? metadata.close() }
        let beforeRead = try attributes(of: metadataDescriptor, type: S_IFREG)
        let limit = 64 * 1024
        guard beforeRead.st_nlink == 1, (1...Int64(limit)).contains(beforeRead.st_size) else {
            throw RunnerMigrationError.unverifiedSource
        }
        let content = try metadata.read(upToCount: limit + 1) ?? Data()
        try Task.checkCancellation()
        let afterRead = try attributes(of: metadataDescriptor, type: S_IFREG)
        guard content.count == beforeRead.st_size, afterRead.st_size == beforeRead.st_size,
              beforeRead.st_ctimespec.tv_sec == afterRead.st_ctimespec.tv_sec,
              beforeRead.st_ctimespec.tv_nsec == afterRead.st_ctimespec.tv_nsec,
              let configuration = try? LocalDotRunnerConfig.decode(from: content),
              configuration.agentId > 0, !configuration.agentName.isEmpty,
              isGitHubScope(configuration.gitHubUrl) else {
            throw RunnerMigrationError.unverifiedSource
        }
        guard configuration.ephemeral != true, configuration.disableUpdate != true else {
            throw RunnerMigrationError.unsupportedSourcePolicy
        }
        return Self(
            rootDirectory: root,
            configuration: configuration,
            directoryIdentity: FileIdentity(directory),
            configurationIdentity: FileIdentity(afterRead)
        )
    }

    func revalidate() throws {
        do {
            guard try Self.inspect(rootDirectory) == self else {
                throw RunnerMigrationError.sourceChanged
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RunnerMigrationError.sourceChanged
        }
    }

    private static func attributes(of descriptor: Int32, type: mode_t) throws -> stat {
        var result = stat()
        guard fstat(descriptor, &result) == 0, result.st_mode & S_IFMT == type,
              result.st_uid == getuid(), result.st_mode & (S_IWGRP | S_IWOTH) == 0 else {
            throw RunnerMigrationError.unverifiedSource
        }
        return result
    }

    static func isGitHubScope(_ url: URL) -> Bool {
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

    private struct FileIdentity: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
        let birthSeconds: Int
        let birthNanoseconds: Int

        init(_ info: stat) {
            device = info.st_dev
            inode = info.st_ino
            birthSeconds = info.st_birthtimespec.tv_sec
            birthNanoseconds = info.st_birthtimespec.tv_nsec
        }
    }
}
