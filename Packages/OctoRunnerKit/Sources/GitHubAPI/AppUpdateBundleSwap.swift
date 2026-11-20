import Darwin
import Foundation

enum AppUpdateBundleSwap {
    /// Both bundles must exist on the same volume. Swapping keeps the previous
    /// app at the candidate path until the caller has confirmed startup.
    static func install(
        candidate: URL, at installed: URL, beforeRollback: @Sendable () throws -> Void = {},
        start: @Sendable (URL) async throws -> Void
    ) async throws {
        try Task.checkCancellation()
        guard swap(candidate, installed) else { throw AppUpdateError.couldNotReplace }
        do {
            try await start(installed)
        } catch AppUpdateError.manualRecoveryRequired {
            throw AppUpdateError.manualRecoveryRequired
        } catch {
            do { try beforeRollback() }
            catch { throw AppUpdateError.manualRecoveryRequired }
            guard swap(candidate, installed) else { throw AppUpdateError.couldNotRestore }
            throw error
        }
    }

    static func swap(_ first: URL, _ second: URL) -> Bool {
        first.withUnsafeFileSystemRepresentation { source in
            second.withUnsafeFileSystemRepresentation { destination in
                guard let source, let destination else { return false }
                return renameatx_np(AT_FDCWD, source, AT_FDCWD, destination, UInt32(RENAME_SWAP)) == 0
            }
        }
    }
}
