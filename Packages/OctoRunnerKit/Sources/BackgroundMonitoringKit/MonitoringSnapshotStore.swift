import Darwin
import Foundation

public struct MonitoringSnapshotStore: Sendable {
    public enum SnapshotError: Error, Equatable {
        case unsupportedVersion(Int)
        case unsafeStorage
        case snapshotTooLarge
    }

    private struct Header: Decodable {
        let version: Int
    }

    private static let maximumSnapshotSize = 1_048_576
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func writeConfiguration(_ configuration: MonitoringConfiguration) throws {
        try write(configuration, to: "configuration.json")
    }

    public func readConfiguration() throws -> MonitoringConfiguration? {
        try read("configuration.json", version: MonitoringConfiguration.currentVersion)
    }

    public func removeConfiguration() throws {
        do {
            try validateDirectory()
            let file = directory.appending(path: "configuration.json")
            guard unlink(file.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch let error as POSIXError where error.code == .ENOENT {
            return
        }
    }

    public func writeObservation(_ observation: MonitoringObservation) throws {
        try write(observation, to: "observation.json")
    }

    public func readObservation(
        for configuration: MonitoringConfiguration,
        at now: Date
    ) throws -> MonitoringObservation? {
        guard let observation: MonitoringObservation = try read("observation.json", version: MonitoringObservation.currentVersion),
              observation.configurationRevision == configuration.revision,
              Set(observation.statuses.keys).isSubset(of: configuration.runners.map(\.id)),
              (-5...60).contains(now.timeIntervalSince(observation.observedAt))
        else { return nil }
        return observation
    }

    private func write<Value: Encodable>(_ value: Value, to filename: String) throws {
        if mkdir(directory.path, 0o700) != 0, errno != EEXIST {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try validateDirectory()
        let data = try JSONEncoder().encode(value)
        guard data.count <= Self.maximumSnapshotSize else { throw SnapshotError.snapshotTooLarge }
        try data.write(to: directory.appending(path: filename), options: .atomic)
    }

    private func read<Value: Decodable>(_ filename: String, version: Int) throws -> Value? {
        do {
            try validateDirectory()
            let fileURL = directory.appending(path: filename)
            let descriptor = open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFREG,
                  metadata.st_uid == geteuid()
            else { throw SnapshotError.unsafeStorage }

            let data = try file.read(upToCount: Self.maximumSnapshotSize + 1) ?? Data()
            guard data.count <= Self.maximumSnapshotSize else { throw SnapshotError.snapshotTooLarge }
            let decoder = JSONDecoder()
            let header = try decoder.decode(Header.self, from: data)
            guard header.version == version else { throw SnapshotError.unsupportedVersion(header.version) }
            return try decoder.decode(Value.self, from: data)
        } catch let error as POSIXError where error.code == .ENOENT {
            return nil
        }
    }

    private func validateDirectory() throws {
        var metadata = stat()
        guard lstat(directory.path, &metadata) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard metadata.st_mode & S_IFMT == S_IFDIR,
              metadata.st_uid == geteuid(),
              metadata.st_mode & (S_IRWXG | S_IRWXO) == 0
        else { throw SnapshotError.unsafeStorage }
    }
}
