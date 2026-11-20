import Foundation
@testable import GitHubAPI
import Testing

struct AppUpdateRecoveryTests {
    @Test("A corrupt archive leaves the installed app and staging directory intact")
    func corruptArchive() async throws {
        try await withUpdateDirectory { directory in
            let archive = directory.appending(path: "broken.zip")
            try Data("not a zip".utf8).write(to: archive)
            let installed = try bundle(in: directory, name: "Installed.app", version: "0.6.0")
            let staging = directory.appending(path: "Staging")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)

            await #expect {
                try await AppUpdateArchive.prepare(
                    archive: archive, in: staging, replacing: installed, expectedVersion: "0.7.0")
            } throws: { error in
                guard case .extractionFailed = error as? AppUpdateError else { return false }
                return true
            }

            #expect(FileManager.default.fileExists(atPath: installed.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
        }
    }

    @Test("Update staging is private and lives directly beside the installed app")
    func durableAppStaging() async throws {
        try await withUpdateDirectory { directory in
            let installed = try bundle(in: directory, name: "Installed.app", version: "0.6.0")
            let staging = try StagedAppUpdate.makeStagingDirectory(beside: installed)
            #expect(staging.deletingLastPathComponent().path == directory.resolvingSymlinksInPath().path)
            let attributes = try FileManager.default.attributesOfItem(atPath: staging.path)
            #expect(attributes[.posixPermissions] as? Int == 0o700)
            let extraction = staging.appending(path: UUID().uuidString)
            let candidate = try bundle(in: extraction, name: "OctoRunner.app", version: "0.7.0")
            let update = StagedAppUpdate(directory: staging, candidate: candidate, installed: installed, version: "0.7.0")
            #expect(update.hasExpectedLayout(beside: installed))
        }
    }

    @Test("A bundle must match the release version and installed app identity", arguments: [
        ("other.example.app", "0.7.0"),
        ("io.octorunner.macos", "0.8.0")
    ])
    func mismatchedBundle(identifier: String, version: String) async throws {
        try await withUpdateDirectory { directory in
            let installed = try bundle(in: directory, name: "Installed.app", version: "0.6.0")
            let candidate = try bundle(in: directory, name: "OctoRunner.app", identifier: identifier, version: version)

            #expect(throws: AppUpdateError.unexpectedBundle) {
                try AppUpdateArchive.validateIdentity(candidate: candidate, installed: installed, expectedVersion: "0.7.0")
            }
        }
    }

    @Test("An installation symlink cannot be exchanged as an app bundle")
    func linkedInstallation() async throws {
        try await withUpdateDirectory { directory in
            let installed = try bundle(in: directory, name: "Installed.app", version: "0.6.0")
            let replacement = try bundle(in: directory, name: "Replacement.app", version: "0.7.0")
            let link = directory.appending(path: "Linked.app")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: installed)
            #expect(throws: AppUpdateError.unexpectedBundle) {
                try AppUpdateArchive.validateIdentity(candidate: replacement, installed: link, expectedVersion: "0.7.0")
            }
        }
    }

    @Test("Matching metadata alone cannot authorize an unsigned replacement")
    func unsignedBundle() async throws {
        try await withUpdateDirectory { directory in
            let installed = try bundle(in: directory, name: "Installed.app", version: "0.6.0")
            let candidate = try bundle(in: directory, name: "OctoRunner.app", version: "0.7.0")

            try AppUpdateArchive.validateIdentity(candidate: candidate, installed: installed, expectedVersion: "0.7.0")
            #expect(throws: AppUpdateError.invalidSignature) {
                try AppUpdateArchive.validateSignature(candidate: candidate, installed: installed)
            }
        }
    }

    @Test("The previous installation remains available until startup succeeds")
    func retainedInstallationOnSuccess() async throws {
        try await withUpdateDirectory { directory in
            let installed = try bundle(in: directory, name: "Installed.app", version: "0.6.0")
            let replacement = try bundle(in: directory, name: "Replacement Bundle.app", version: "0.7.0")

            try await AppUpdateBundleSwap.install(candidate: replacement, at: installed) { url in
                #expect(Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String == "0.7.0")
                #expect(Bundle(url: replacement)?.infoDictionary?["CFBundleShortVersionString"] as? String == "0.6.0")
            }
        }
    }

    @Test("Developer ID releases pass Gatekeeper and retain the old signed app after rollback",
          .enabled(if: ProcessInfo.processInfo.environment["OCTORUNNER_SIGNED_UPDATE_FIXTURES"] != nil))
    func signedReleaseReplacement() async throws {
        let location = try #require(ProcessInfo.processInfo.environment["OCTORUNNER_SIGNED_UPDATE_FIXTURES"])
        let fixtures = URL(filePath: location, directoryHint: .isDirectory)
        try await withUpdateDirectory { directory in
            let oldArchive = fixtures.appending(path: "OctoRunner-0.5.2-arm64.zip")
            let newArchive = fixtures.appending(path: "OctoRunner-0.6.0-arm64.zip")
            let extraction = Process()
            extraction.executableURL = URL(filePath: "/usr/bin/ditto")
            extraction.arguments = ["-x", "-k", oldArchive.path, directory.path]
            try extraction.run()
            extraction.waitUntilExit()
            try #require(extraction.terminationStatus == 0)
            let installed = directory.appending(path: "OctoRunner.app")
            let staging = try StagedAppUpdate.makeStagingDirectory(beside: installed)
            let candidate = try await AppUpdateArchive.prepare(
                archive: newArchive, in: staging, replacing: installed, expectedVersion: "0.6.0")

            await #expect(throws: AppUpdateError.couldNotStart) {
                try await AppUpdateBundleSwap.install(candidate: candidate, at: installed) { app in
                    #expect(AppUpdateArchive.version(of: app) == "0.6.0")
                    throw AppUpdateError.couldNotStart
                }
            }
            #expect(AppUpdateArchive.version(of: installed) == "0.5.2")
            try AppUpdateArchive.validateSignature(candidate: candidate, installed: installed)
            try await AppUpdateBundleSwap.install(candidate: candidate, at: installed) { app in
                #expect(AppUpdateArchive.version(of: app) == "0.6.0")
            }
            #expect(AppUpdateArchive.version(of: candidate) == "0.5.2")
            try AppUpdateArchive.validateSignature(candidate: candidate, installed: installed)
        }
    }

    @Test("A failed startup restores the previous app at the same installation path")
    func failedStartup() async throws {
        try await withUpdateDirectory { directory in
            let installed = try bundle(in: directory, name: "Installed.app", version: "0.6.0")
            let replacement = try bundle(in: directory, name: "Replacement.app", version: "0.7.0")
            let oldInfo = try Data(contentsOf: installed.appending(path: "Contents/Info.plist"))
            let newInfo = try Data(contentsOf: replacement.appending(path: "Contents/Info.plist"))

            await #expect(throws: CocoaError(.executableLoad)) {
                try await AppUpdateBundleSwap.install(candidate: replacement, at: installed) { _ in
                    throw CocoaError(.executableLoad)
                }
            }

            #expect(try Data(contentsOf: installed.appending(path: "Contents/Info.plist")) == oldInfo)
            #expect(try Data(contentsOf: replacement.appending(path: "Contents/Info.plist")) == newInfo)
        }
    }

    @Test("A missing candidate prevents any move of the old application")
    func missingCandidate() async throws {
        try await withUpdateDirectory { directory in
            let installed = try bundle(in: directory, name: "Installed.app", version: "0.6.0")
            let replacement = directory.appending(path: "Missing.app")
            await #expect(throws: AppUpdateError.couldNotReplace) {
                try await AppUpdateBundleSwap.install(candidate: replacement, at: installed) { _ in
                    Issue.record("Unexpected attempt to start a missing app")
                }
            }
            #expect(FileManager.default.fileExists(atPath: installed.path))
        }
    }

    @Test("Rollback restores the SQLite store and its WAL together")
    func restoresStoreAndWriteAheadLog() async throws {
        try await withUpdateDirectory { directory in
            let store = directory.appending(path: "Data")
            try FileManager.default.createDirectory(at: store, withIntermediateDirectories: false)
            let database = store.appending(path: "octorunner.store")
            let wal = store.appending(path: "octorunner.store-wal")
            let workspace = store.appending(path: "runners/test/_work")
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            let liveLog = workspace.appending(path: "job.log")
            try Data("initial job output".utf8).write(to: liveLog)
            try Data("before update".utf8).write(to: database)
            try Data("pending SQLite edits".utf8).write(to: wal)
            let backup = try AppUpdateStoreBackup(store: database)
            defer { backup.discard() }

            try Data("after update".utf8).write(to: database)
            try FileManager.default.removeItem(at: wal)
            try Data("new output from a live runner".utf8).write(to: liveLog)
            try backup.restore()
            #expect(try Data(contentsOf: database) == Data("before update".utf8))
            #expect(try Data(contentsOf: wal) == Data("pending SQLite edits".utf8))
            #expect(try Data(contentsOf: liveLog) == Data("new output from a live runner".utf8))
        }
    }

    @Test("A pending update prevents other app instances from opening the store")
    func storeLock() async throws {
        try await withUpdateDirectory { directory in
            let lock = directory.appending(path: "update.lock")
            var installer = try AppUpdateStoreLease(lock: lock, exclusive: true)
            #expect(installer != nil)
            #expect(try AppUpdateStoreLease(lock: lock, exclusive: false) == nil)
            installer = nil
            let application = try AppUpdateStoreLease(lock: lock, exclusive: false)
            #expect(application != nil)
            let unexpectedInstaller = try AppUpdateStoreLease(lock: lock, exclusive: true)
            #expect(unexpectedInstaller == nil)
            withExtendedLifetime(application) {}
        }
    }

    @Test("Candidate startup is exclusive and a dead installer cannot authorize a late launch")
    func candidateStartupLease() async throws {
        try await withUpdateDirectory { directory in
            let installerLock = directory.appending(path: "installer.lock")
            let candidateLock = directory.appending(path: "candidate.lock")
            let initial = try AppUpdateStoreLease.authorizeCandidate(installerLock: installerLock, candidateLock: candidateLock)
            #expect(initial == nil)
            var installer = try AppUpdateStoreLease(lock: installerLock, exclusive: true)
            #expect(installer != nil)
            var candidate = try AppUpdateStoreLease.authorizeCandidate(installerLock: installerLock, candidateLock: candidateLock)
            #expect(candidate != nil)
            let overlappingCandidate = try AppUpdateStoreLease.authorizeCandidate(installerLock: installerLock, candidateLock: candidateLock)
            #expect(overlappingCandidate == nil)
            installer = nil
            let overlappingRecovery = try AppUpdateStoreLease(lock: candidateLock, exclusive: true)
            #expect(overlappingRecovery == nil)
            withExtendedLifetime(candidate) {}
            candidate = nil
            let lateCandidate = try AppUpdateStoreLease.authorizeCandidate(installerLock: installerLock, candidateLock: candidateLock)
            #expect(lateCandidate == nil)
            let recovery = try AppUpdateStoreLease(lock: candidateLock, exclusive: true)
            #expect(recovery != nil)
        }
    }

    @Test("An incomplete backup never replaces or removes current store files")
    func incompleteStoreBackup() async throws {
        try await withUpdateDirectory { directory in
            let database = directory.appending(path: "octorunner.store")
            let wal = directory.appending(path: "octorunner.store-wal")
            let current = Data("current contents".utf8)
            try Data("original contents".utf8).write(to: database)
            try Data("original WAL".utf8).write(to: wal)
            let backup = try AppUpdateStoreBackup(store: database)
            defer { backup.discard() }
            struct StoredLocation: Decodable { let directory: URL }
            let url = try JSONDecoder().decode(StoredLocation.self, from: JSONEncoder().encode(backup)).directory
            try FileManager.default.removeItem(at: url.appending(path: "Store-wal"))
            try current.write(to: database)
            try current.write(to: wal)

            #expect(throws: CocoaError.self) { try backup.restore() }
            #expect(try Data(contentsOf: database) == current)
            #expect(try Data(contentsOf: wal) == current)
        }
    }

    @Test("A backup can only restore the store recorded at the expected app data location")
    func backupStoreLocation() async throws {
        try await withUpdateDirectory { directory in
            let database = directory.appending(path: "octorunner.store")
            let backup = try AppUpdateStoreBackup(store: database)
            defer { backup.discard() }
            #expect(backup.hasExpectedLayout(for: database))
            #expect(!backup.hasExpectedLayout(for: directory.appending(path: "another.store")))
        }
    }

    @Test("An interrupted swap can be rolled back using the saved journal")
    func restoreAfterInterruption() async throws {
        try await withUpdateDirectory { directory in
            let installed = try bundle(in: directory, name: "Installed.app", version: "0.6.0")
            let replacement = try bundle(in: directory, name: "Replacement.app", version: "0.7.0")
            let database = directory.appending(path: "octorunner.store")
            let original = Data("original app state".utf8)
            try original.write(to: database)
            let store = try AppUpdateStoreBackup(store: database)
            defer { store.discard() }
            let update = StagedAppUpdate(directory: directory, candidate: replacement, installed: installed, version: "0.7.0")
            let journal = AppUpdateJournal(update: update, previousVersion: "0.6.0", store: store)
            let persisted = try JSONEncoder().encode(journal)
            #expect(AppUpdateBundleSwap.swap(replacement, installed))
            try Data("candidate app state".utf8).write(to: database)

            let recovered = try JSONDecoder().decode(AppUpdateJournal.self, from: persisted)
            try recovered.rollback()
            try recovered.rollback()
            #expect(AppUpdateArchive.version(of: installed) == "0.6.0")
            #expect(try Data(contentsOf: database) == original)
        }
    }

    @Test("Recovery keeps the previous app private until its store backup can be restored")
    func holdsPreviousAppDuringFailedRestore() async throws {
        try await withUpdateDirectory { directory in
            let installed = try bundle(in: directory, name: "Installed.app", version: "0.6.0")
            let replacement = try bundle(in: directory, name: "Replacement.app", version: "0.7.0")
            let database = directory.appending(path: "octorunner.store")
            try Data("original local state".utf8).write(to: database)
            let store = try AppUpdateStoreBackup(store: database)
            let current = Data("changed local state".utf8)
            let update = StagedAppUpdate(directory: directory, candidate: replacement, installed: installed, version: "0.7.0")
            let journal = AppUpdateJournal(update: update, previousVersion: "0.6.0", store: store)
            #expect(AppUpdateBundleSwap.swap(replacement, installed))
            try current.write(to: database)
            store.discard()

            #expect(throws: (any Error).self) { try journal.rollback() }
            #expect(AppUpdateArchive.version(of: installed) == "0.7.0")
            #expect(AppUpdateArchive.version(of: replacement) == "0.6.0")
            #expect(try Data(contentsOf: database) == current)
        }
    }

    private func withUpdateDirectory(_ operation: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "App Update Tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await operation(directory)
    }

    private func bundle(in directory: URL, name: String, identifier: String = "io.octorunner.macos", version: String) throws -> URL {
        let result = directory.appending(path: name)
        let contents = result.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let metadata = [
            "CFBundleIdentifier": identifier, "CFBundleShortVersionString": version,
            "CFBundleExecutable": "OctoRunner", "CFBundlePackageType": "APPL"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        return result
    }
}
