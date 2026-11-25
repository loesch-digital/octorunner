import Darwin
import Foundation

public struct MonitoringLease: Sendable {
    private let lockFile: URL

    public init(lockFile: URL) {
        self.lockFile = lockFile
    }

    /// The operation must complete its monitoring and notification work before returning.
    public func withOwnership<Result: Sendable>(
        _ operation: @Sendable () async throws -> Result
    ) async throws -> Result? {
        try Task.checkCancellation()
        let descriptor = open(lockFile.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        // Leave the file in place so every process locks the same inode.
        defer { close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_uid == geteuid(),
              metadata.st_mode & (S_IRWXG | S_IRWXO) == 0
        else { throw POSIXError(.EACCES) }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            if failure == EWOULDBLOCK { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        try Task.checkCancellation()
        return try await operation()
    }
}
