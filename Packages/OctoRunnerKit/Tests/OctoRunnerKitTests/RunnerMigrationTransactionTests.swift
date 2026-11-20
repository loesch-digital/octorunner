import Foundation
@testable import RunnerEngine
import Testing

struct RunnerMigrationTransactionTests {
    @Test("Only successful registration updates the model and enables startup", arguments: [
        MigrationFailure.staging, .verification, .registration, .commit, .startup, .none
    ])
    func preservesSingleInstallation(_ failure: MigrationFailure) async throws {
        let fixture = try MigrationSourceFixture()
        defer { fixture.remove() }
        let request = try fixture.request()
        let plan = RunnerMigrationPlan(
            destination: fixture.managed.appending(path: request.name),
            group: nil, customLabels: ["xcode"], request: request,
            source: try RunnerMigrationSource.inspect(fixture.source)
        )
        let privateKey = fixture.source.appending(path: ".credentials_rsaparams")
        let marker = Data("synthetic test marker".utf8)
        try marker.write(to: privateKey)
        let journal = RunnerMigrationJournal(directory: fixture.directory.appending(path: "journals"))
        let coordinator = RunnerMigrationCoordinator(journal: journal)
        let operations = MigrationOperationsStub(failure: failure)

        if failure == .none {
            let newID = try await coordinator.migrate(plan, operations: operations)
            #expect(newID == 37)
        } else if [.staging, .verification].contains(failure) {
            await #expect(throws: failure) { try await coordinator.migrate(plan, operations: operations) }
        } else {
            await #expect(throws: RunnerMigrationError.recoveryRequired) {
                try await coordinator.migrate(plan, operations: operations)
            }
        }

        #expect(try Data(contentsOf: privateKey) == marker)
        #expect(!FileManager.default.fileExists(atPath: plan.destination.appending(path: ".credentials_rsaparams").path))
        let localFiles = (try? FileManager.default.contentsOfDirectory(atPath: fixture.managed.path)) ?? []
        #expect(localFiles.sorted() == ([.staging, .verification].contains(failure) ? [] : [request.name]))
        let recovery = try journal.pending(request.runnerID)
        let performed = await operations.performed
        switch failure {
        case .staging, .verification:
            #expect(recovery == nil)
            #expect(!performed.contains(.registration))
        case .registration:
            #expect(recovery?.stage == .registering)
            #expect(recovery?.newRemoteID == nil)
            #expect(!performed.contains(.commit))
        case .commit:
            #expect(recovery?.stage == .committing)
            #expect(recovery?.newRemoteID == 37)
            #expect(!performed.contains(.startup))
        case .startup:
            #expect(recovery?.stage == .starting)
            #expect(recovery?.newRemoteID == 37)
            #expect(performed == [.staging, .verification, .registration, .commit, .startup])
        case .none:
            #expect(recovery == nil)
            #expect(performed == [.staging, .verification, .registration, .commit, .startup])
        }
    }

    @Test("After an interrupted registration a fresh coordinator never issues a second replace")
    func rejectsRetryAfterInterruption() async throws {
        let fixture = try MigrationSourceFixture()
        defer { fixture.remove() }
        let request = try fixture.request()
        let plan = RunnerMigrationPlan(
            destination: fixture.managed.appending(path: request.name),
            group: nil, customLabels: ["xcode"], request: request,
            source: try RunnerMigrationSource.inspect(fixture.source)
        )
        let journal = RunnerMigrationJournal(directory: fixture.directory.appending(path: "journals"))
        let initial = RunnerMigrationCoordinator(journal: journal)
        let failingOperations = MigrationOperationsStub(failure: .registration)
        await #expect(throws: RunnerMigrationError.recoveryRequired) {
            try await initial.migrate(plan, operations: failingOperations)
        }

        let newCoordinator = RunnerMigrationCoordinator(journal: journal)
        let unexpectedOperations = MigrationOperationsStub(failure: .none)
        await #expect(throws: RunnerMigrationError.recoveryRequired) {
            try await newCoordinator.migrate(plan, operations: unexpectedOperations)
        }
        #expect(await unexpectedOperations.performed.isEmpty)
    }

    @Test("Recovery can discard a proven pre-registration candidate without touching the original installation")
    func discardsInterruptedPreparation() async throws {
        let fixture = try MigrationSourceFixture()
        defer { fixture.remove() }
        let request = try fixture.request()
        try FileManager.default.createDirectory(at: fixture.managed, withIntermediateDirectories: true)
        let destination = fixture.managed.appending(path: request.name)
        let staged = fixture.managed.appending(path: ".migration-\(request.runnerID.uuidString)")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        let journal = RunnerMigrationJournal(directory: fixture.directory.appending(path: "journals"))
        let identity = try RunnerMigrationRecovery.Artifact.read(at: staged)
        let fingerprint = try #require(identity)
        let entry = RunnerMigrationRecovery(runnerID: request.runnerID, oldRemoteID: 21, newRemoteID: nil,
            source: fixture.source, destination: destination, stage: .preparing, artifact: fingerprint)
        try journal.begin(entry)

        let coordinator = RunnerMigrationCoordinator(journal: journal)
        try await coordinator.discardPreparation(for: request.runnerID, in: fixture.managed)

        #expect(try journal.pending(request.runnerID) == nil)
        #expect(!FileManager.default.fileExists(atPath: staged.path))
        #expect(FileManager.default.fileExists(atPath: fixture.metadata.path))
    }

    @Test("A staging reservation left before recording its identity can be cleared only when empty", arguments: [false, true])
    func discardsEmptyReservationAfterCrash(hasContents: Bool) async throws {
        let fixture = try MigrationSourceFixture()
        defer { fixture.remove() }
        let request = try fixture.request()
        try FileManager.default.createDirectory(at: fixture.managed, withIntermediateDirectories: true)
        let staged = try RunnerProvisionerActor.createInstanceDirectory(name: ".migration-\(request.runnerID.uuidString)", in: fixture.managed)
        if hasContents { try Data("keep".utf8).write(to: staged.appending(path: "keep")) }
        let journal = RunnerMigrationJournal(directory: fixture.directory.appending(path: "journals"))
        try journal.begin(RunnerMigrationRecovery(runnerID: request.runnerID, oldRemoteID: 21, newRemoteID: nil,
            source: fixture.source, destination: fixture.managed.appending(path: request.name), stage: .preparing))
        let coordinator = RunnerMigrationCoordinator(journal: journal)
        if hasContents {
            await #expect(throws: RunnerMigrationError.recoveryRequired) {
                try await coordinator.discardPreparation(for: request.runnerID, in: fixture.managed)
            }
            #expect(try journal.pending(request.runnerID) != nil)
            #expect(FileManager.default.fileExists(atPath: staged.appending(path: "keep").path))
            return
        }

        try await coordinator.discardPreparation(for: request.runnerID, in: fixture.managed)

        #expect(try journal.pending(request.runnerID) == nil)
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test("Recovery never discards files after the registration may have started")
    func doesNotDiscardAnUncertainRegistration() async throws {
        let fixture = try MigrationSourceFixture()
        defer { fixture.remove() }
        let request = try fixture.request()
        let destination = fixture.managed.appending(path: request.name)
        let journal = RunnerMigrationJournal(directory: fixture.directory.appending(path: "journals"))
        let entry = RunnerMigrationRecovery(runnerID: request.runnerID, oldRemoteID: 21, newRemoteID: nil,
            source: fixture.source, destination: destination, stage: .registering)
        try journal.begin(entry)
        let coordinator = RunnerMigrationCoordinator(journal: journal)

        await #expect(throws: RunnerMigrationError.recoveryRequired) {
            try await coordinator.discardPreparation(for: request.runnerID, in: fixture.managed)
        }
        #expect(try journal.pending(request.runnerID) == entry)
    }

    @Test("A restart uses the committed registration without calling registration again")
    func retriesKnownStart() async throws {
        let fixture = try MigrationSourceFixture()
        defer { fixture.remove() }
        let request = try fixture.request()
        let destination = fixture.managed.appending(path: request.name)
        let plan = RunnerMigrationPlan(destination: destination, group: nil, customLabels: ["xcode"],
            request: request, source: try RunnerMigrationSource.inspect(fixture.source))
        let journal = RunnerMigrationJournal(directory: fixture.directory.appending(path: "journals"))
        let coordinator = RunnerMigrationCoordinator(journal: journal)
        await #expect(throws: RunnerMigrationError.recoveryRequired) {
            try await coordinator.migrate(plan, operations: MigrationOperationsStub(failure: .startup))
        }
        await #expect(throws: RunnerMigrationError.recoveryRequired) {
            try await coordinator.retryStartup(for: request.runnerID, destination: destination, remoteID: 38) { _ in
                Issue.record("A different remote identity must never be started")
            }
        }
        try await coordinator.retryStartup(for: request.runnerID, destination: destination, remoteID: 37) { entry in
            #expect(entry.source == plan.sourceDirectory)
            #expect(entry.newRemoteID == 37)
        }
        #expect(try journal.pending(request.runnerID) == nil)
    }

    @Test("An interrupted model commit can be resumed with the verified runner and original mode")
    func retriesVerifiedCommitAndStartup() async throws {
        let fixture = try MigrationSourceFixture()
        defer { fixture.remove() }
        let request = try fixture.request()
        let destination = fixture.managed.appending(path: request.name)
        let plan = RunnerMigrationPlan(destination: destination, group: nil, customLabels: ["xcode"],
            request: request, source: try RunnerMigrationSource.inspect(fixture.source))
        let journal = RunnerMigrationJournal(directory: fixture.directory.appending(path: "journals"))
        let coordinator = RunnerMigrationCoordinator(journal: journal)
        await #expect(throws: RunnerMigrationError.recoveryRequired) {
            try await coordinator.migrate(plan, operations: MigrationOperationsStub(failure: .commit))
        }
        try await coordinator.retryStartup(for: request.runnerID, destination: destination, remoteID: 37, commit: { entry in
            let stage = try journal.pending(request.runnerID)?.stage
            #expect(stage == .committing)
            #expect(entry.launchAgent == true)
            #expect(entry.version == "fixture-version")
        }) { _ in
            let stage = try journal.pending(request.runnerID)?.stage
            #expect(stage == .starting)
        }
        #expect(try journal.pending(request.runnerID) == nil)
    }
}

enum MigrationFailure: Error, Sendable, Equatable {
    case staging, verification, registration, commit, startup, none
}

private actor MigrationOperationsStub: RunnerMigrationOperations {
    let failure: MigrationFailure
    private(set) var performed: [MigrationFailure] = []

    init(failure: MigrationFailure) {
        self.failure = failure
    }

    func stage(at destination: URL) throws -> String {
        try perform(.staging)
        try Data("downloaded fixture".utf8).write(to: destination.appending(path: "run.sh"))
        return "fixture-version"
    }

    func verifyBeforeRegistration() throws {
        try perform(.verification)
    }

    func register() throws -> Int64 {
        try perform(.registration)
        return 37
    }

    func commit(newRemoteID: Int64) throws {
        #expect(newRemoteID == 37)
        try perform(.commit)
    }

    func start() throws {
        try perform(.startup)
    }

    private func perform(_ operation: MigrationFailure) throws {
        performed.append(operation)
        if operation == failure { throw operation }
    }
}
