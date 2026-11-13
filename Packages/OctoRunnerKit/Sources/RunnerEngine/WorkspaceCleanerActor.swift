import Foundation
import Darwin

public actor WorkspaceCleanerActor {
    private let base: URL
    public nonisolated let baseRunnersDirectory: URL
    private var isCleaning = false

    public nonisolated static var managedBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "io.octorunner.macos/runners", directoryHint: .isDirectory)
    }

    public init(baseRunnersDirectory: URL? = nil) {
        base = baseRunnersDirectory ?? Self.managedBaseDirectory
        self.baseRunnersDirectory = base
    }

    public func inspect(runners: [ManagedStorageRunner], workspaceAgeDays: Int, logRetentionDays: Int, now: Date = .now) throws -> StorageUsageSnapshot {
        var totals: [String: Int64] = [:]
        var candidates: [StorageCleanupCandidate] = []
        var budget = 100_000
        for runner in runners {
            try Task.checkCancellation()
            let root = try validatedRoot(runner)
            for folder in ["_work", "_diag"] {
                let parent = root.appending(path: folder)
                guard let parentInfo = metadata(parent), parentInfo.directory else { continue }
                let children = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
                let newestLog = folder == "_diag" ? children.filter { isDiagnosticLog($0.lastPathComponent) }
                    .compactMap { url -> (URL, Date)? in
                        guard let info = metadata(url), !info.directory else { return nil }
                        return (url, info.modified)
                    }.max(by: { $0.1 < $1.1 })?.0 : nil
                for child in children {
                    guard let info = try measure(child, budget: &budget, depth: 0) else { continue }
                    let name = child.lastPathComponent
                    let category = folder == "_diag" ? "logs" : name == "_actions" ? "actions" : name == "_temp" ? "temporary" : "workspaces"
                    let sum = (totals[category] ?? 0).addingReportingOverflow(info.bytes)
                    guard !sum.overflow else { throw CocoaError(.fileReadTooLarge) }
                    totals[category] = sum.partialValue
                    let age = folder == "_diag" ? logRetentionDays : workspaceAgeDays
                    let allowed = folder == "_diag"
                        ? !info.directory && isDiagnosticLog(name) && child != newestLog
                        : info.directory && isWorkspace(name)
                    guard allowed, info.modified < cutoff(days: age, now: now) else { continue }
                    candidates.append(StorageCleanupCandidate(runnerID: runner.id, relativePath: "\(folder)/\(name)", category: category,
                        logicalBytes: info.bytes, modifiedAt: info.modified, inode: info.inode, device: info.device))
                }
            }
        }
        return StorageUsageSnapshot(logicalBytesByCategory: totals, candidates: candidates.sorted { $0.modifiedAt < $1.modifiedAt }, observedAt: now)
    }

    public func clean(_ candidates: [StorageCleanupCandidate], runners: [ManagedStorageRunner], checker: any StorageRunnerStateChecking,
                      workspaceAgeDays: Int, logRetentionDays: Int, now: Date = .now, stopWhenAvailableBytes: Int64? = nil) async throws -> StorageCleanupReport {
        guard !isCleaning else { return StorageCleanupReport(removedCount: 0, removedLogicalBytes: 0, skippedCount: candidates.count) }
        isCleaning = true
        defer { isCleaning = false }
        var removed = 0, skipped = 0
        var bytes: Int64 = 0
        let groups = Dictionary(grouping: runners, by: \.id)
        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            if let threshold = stopWhenAvailableBytes {
                let freshURL = URL(fileURLWithPath: base.path(percentEncoded: false))
                guard let available = try freshURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage else { throw CocoaError(.fileReadUnknown) }
                if available >= threshold { skipped += candidates.count - index; break }
            }
            guard let matches = groups[candidate.runnerID], matches.count == 1, let runner = matches.first,
                  (try? await checker.isStopped(runner)) == true else {
                try Task.checkCancellation()
                skipped += 1; continue
            }
            try Task.checkCancellation()
            // The preview is not authority: recompute identity, age and protected
            // paths after suspension, immediately before each mutation.
            let fresh = try inspect(runners: [runner], workspaceAgeDays: workspaceAgeDays, logRetentionDays: logRetentionDays, now: now)
            guard let current = fresh.candidates.first(where: { $0.id == candidate.id }),
                  current.modifiedAt == candidate.modifiedAt, current.logicalBytes == candidate.logicalBytes else { skipped += 1; continue }
            guard (try? await checker.isStopped(runner)) == true else {
                try Task.checkCancellation()
                skipped += 1; continue
            }
            let finalSnapshot = try inspect(runners: [runner], workspaceAgeDays: workspaceAgeDays, logRetentionDays: logRetentionDays, now: now)
            guard let unchanged = finalSnapshot.candidates.first(where: { $0.id == current.id }),
                  unchanged.modifiedAt == current.modifiedAt, unchanged.logicalBytes == current.logicalBytes else { skipped += 1; continue }
            let root = try validatedRoot(runner)
            let target = root.appending(path: current.relativePath)
            try Task.checkCancellation()
            guard let final = metadata(target), final.inode == current.inode, final.device == current.device else { skipped += 1; continue }
            try FileManager.default.removeItem(at: target)
            removed += 1
            bytes += current.logicalBytes
        }
        return StorageCleanupReport(removedCount: removed, removedLogicalBytes: bytes, skippedCount: skipped)
    }

    private func validatedRoot(_ runner: ManagedStorageRunner) throws -> URL {
        let root = runner.root.standardizedFileURL
        // Validate the original spelling: standardizedFileURL can resolve links
        // and would hide precisely the ancestors we must reject.
        var ancestor = runner.root
        while ancestor.path != "/" {
            guard metadata(ancestor)?.directory == true else { throw CocoaError(.fileReadNoPermission) }
            ancestor.deleteLastPathComponent()
        }
        guard runner.root.isFileURL, root.deletingLastPathComponent().pathComponents == base.standardizedFileURL.pathComponents,
              metadata(base.deletingLastPathComponent())?.directory == true,
              metadata(base)?.directory == true, metadata(root)?.directory == true else { throw CocoaError(.fileReadNoPermission) }
        return runner.root
    }

    private func isDiagnosticLog(_ name: String) -> Bool {
        name.hasSuffix(".log") && (name.hasPrefix("Runner_") || name.hasPrefix("Worker_"))
    }

    private func isWorkspace(_ name: String) -> Bool {
        name == "_actions" || name == "_temp" || (!name.hasPrefix("_") && !name.hasPrefix("."))
    }

    private func cutoff(days: Int, now: Date) -> Date {
        now.addingTimeInterval(-Double(min(max(days, 1), 365)) * 86_400)
    }

    private func metadata(_ url: URL) -> (directory: Bool, bytes: Int64, modified: Date, inode: UInt64, device: Int32)? {
        var value = stat()
        // POSIX lstat("link/") follows the directory link. Strip URL directory
        // hints before checking each component so links remain observable.
        var path = url.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        guard path.withCString({ lstat($0, &value) }) == 0 else { return nil }
        let kind = value.st_mode & S_IFMT
        guard kind == S_IFDIR || kind == S_IFREG else { return nil }
        return (kind == S_IFDIR, kind == S_IFREG ? max(0, value.st_size) : 0,
            Date(timeIntervalSince1970: Double(value.st_mtimespec.tv_sec) + Double(value.st_mtimespec.tv_nsec) / 1_000_000_000),
            value.st_ino, value.st_dev)
    }

    private func measure(_ url: URL, budget: inout Int, depth: Int) throws -> (directory: Bool, bytes: Int64, modified: Date, inode: UInt64, device: Int32)? {
        try Task.checkCancellation()
        budget -= 1
        guard budget >= 0, depth <= 64 else { throw CocoaError(.fileReadTooLarge) }
        guard var info = metadata(url) else { return nil } // Never follow symlinks or special files.
        if info.directory {
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                guard let nested = try measure(child, budget: &budget, depth: depth + 1) else { continue }
                let sum = info.bytes.addingReportingOverflow(nested.bytes)
                guard !sum.overflow else { throw CocoaError(.fileReadTooLarge) }
                info.bytes = sum.partialValue
                info.modified = max(info.modified, nested.modified)
            }
        }
        return info
    }
}
