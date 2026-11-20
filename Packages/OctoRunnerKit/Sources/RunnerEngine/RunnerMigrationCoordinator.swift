import Darwin
import Foundation

protocol RunnerMigrationOperations: Sendable {
    func stage(at destination: URL) async throws -> String
    func verifyBeforeRegistration() async throws
    func register() async throws -> Int64
    func commit(newRemoteID: Int64) async throws
    func start() async throws
}

/// Replacing a registration can invalidate the old credentials before the
/// command returns. Persist that boundary before invoking the command.
actor RunnerMigrationCoordinator {
    private let journal: RunnerMigrationJournal

    init(journal: RunnerMigrationJournal) {
        self.journal = journal
    }

    func migrate(_ plan: RunnerMigrationPlan, operations: any RunnerMigrationOperations) async throws -> Int64 {
        try Task.checkCancellation()
        let lock = try journal.lock()
        defer { close(lock) }
        var entry = RunnerMigrationRecovery(
            runnerID: plan.runnerID, oldRemoteID: plan.request.remoteRunnerID, newRemoteID: nil,
            source: plan.sourceDirectory, destination: plan.destination, stage: .preparing, launchAgent: plan.launchAgent
        )
        try journal.begin(entry)

        var candidate: Candidate?
        var registrationMayHaveChanged = false
        do {
            candidate = try Candidate.create(beside: plan.destination, runnerID: plan.runnerID)
            guard let staged = candidate else { throw RunnerMigrationError.recoveryRequired }
            entry = entry.at(.preparing, artifact: staged.identity)
            try journal.update(entry)
            let version = try await operations.stage(at: staged.directory)
            try await operations.verifyBeforeRegistration()
            try Task.checkCancellation()
            try plan.source.revalidate()
            try candidate?.publish(to: plan.destination)

            entry = entry.at(.registering, version: version)
            try journal.update(entry)
            registrationMayHaveChanged = true
            let newID = try await operations.register()
            guard newID > 0 else { throw RunnerMigrationError.runnerIdentityMismatch }
            entry = entry.at(.registered, newRemoteID: newID)
            try journal.update(entry)

            // Save the identity before enabling starts. Once GitHub can send
            // jobs to the replacement it may be unsafe to stop it again.
            entry = entry.at(.committing)
            try journal.update(entry)
            try await operations.commit(newRemoteID: newID)
            entry = entry.at(.starting)
            try journal.update(entry)
            try await operations.start()
            try journal.complete(entry.runnerID)
            return newID
        } catch {
            if registrationMayHaveChanged { throw RunnerMigrationError.recoveryRequired }
            do {
                try candidate?.remove()
                try journal.complete(entry.runnerID)
            } catch {
                throw RunnerMigrationError.recoveryRequired
            }
            throw error
        }
    }

    func discardPreparation(for runnerID: UUID, in managedDirectory: URL) throws {
        try Task.checkCancellation()
        let lock = try journal.lock()
        defer { close(lock) }
        guard let entry = try journal.pending(runnerID), entry.stage == .preparing,
              entry.destination.deletingLastPathComponent().standardizedFileURL.path == managedDirectory.standardizedFileURL.path,
              entry.source.standardizedFileURL.path != entry.destination.standardizedFileURL.path else {
            throw RunnerMigrationError.recoveryRequired
        }
        let staged = managedDirectory.appending(path: Candidate.name(for: runnerID), directoryHint: .isDirectory)
        let stagedIdentity = try RunnerMigrationRecovery.Artifact.read(at: staged)
        if let stagedIdentity {
            if let recorded = entry.artifact {
                guard stagedIdentity == recorded else { throw RunnerMigrationError.recoveryRequired }
                try Candidate(directory: staged, identity: stagedIdentity).remove()
            } else {
                // The only unrecorded artifact can be the private, empty
                // directory reserved before staging began. rmdir never
                // deletes a symlink or anything from a nonempty directory.
                var info = stat()
                guard lstat(staged.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                      info.st_uid == getuid(), info.st_mode & 0o777 == 0o700,
                      rmdir(staged.path) == 0 else { throw RunnerMigrationError.recoveryRequired }
            }
        } else if let registeredIdentity = entry.artifact,
                  try RunnerMigrationRecovery.Artifact.read(at: entry.destination) == registeredIdentity {
            try Candidate(directory: entry.destination, identity: registeredIdentity).remove()
        }
        try journal.complete(runnerID)
    }

    func retryStartup(for runnerID: UUID, destination: URL, remoteID: Int64,
                      commit: (@Sendable (RunnerMigrationRecovery) async throws -> Void)? = nil,
                      perform: @Sendable (RunnerMigrationRecovery) async throws -> Void) async throws {
        try Task.checkCancellation()
        let lock = try journal.lock()
        defer { close(lock) }
        guard let entry = try journal.pending(runnerID),
              entry.newRemoteID == remoteID, entry.destination.standardizedFileURL.path == destination.standardizedFileURL.path,
              let artifact = entry.artifact, try RunnerMigrationRecovery.Artifact.read(at: destination) == artifact else {
            throw RunnerMigrationError.recoveryRequired
        }
        if let commit {
            guard [.registered, .committing].contains(entry.stage) else { throw RunnerMigrationError.recoveryRequired }
            let committing = entry.at(.committing)
            try journal.update(committing)
            try await commit(committing)
        } else if ![.starting, .committing].contains(entry.stage) {
            throw RunnerMigrationError.recoveryRequired
        }
        let restarting = entry.at(.starting)
        try journal.update(restarting)
        try await perform(restarting)
        try journal.complete(runnerID)
    }

    private struct Candidate {
        var directory: URL
        let identity: RunnerMigrationRecovery.Artifact

        static func name(for runnerID: UUID) -> String {
            ".migration-\(runnerID.uuidString)"
        }

        static func create(beside destination: URL, runnerID: UUID) throws -> Self {
            let base = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            guard try RunnerMigrationRecovery.Artifact.read(at: base) != nil else {
                throw RunnerMigrationError.recoveryRequired
            }
            let root = try RunnerProvisionerActor.createInstanceDirectory(name: name(for: runnerID), in: base)
            guard let identity = try RunnerMigrationRecovery.Artifact.read(at: root) else {
                throw RunnerMigrationError.recoveryRequired
            }
            return Self(directory: root, identity: identity)
        }

        mutating func publish(to destination: URL) throws {
            try verifyIdentity()
            if renamex_np(directory.path, destination.path, UInt32(RENAME_EXCL)) != 0 {
                if errno == EEXIST { throw RunnerEngineError.runnerDirectoryAlreadyExists }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            directory = destination
        }

        func remove() throws {
            try verifyIdentity()
            try FileManager.default.removeItem(at: directory)
        }

        private func verifyIdentity() throws {
            guard try RunnerMigrationRecovery.Artifact.read(at: directory) == identity else {
                throw RunnerMigrationError.recoveryRequired
            }
        }
    }
}
