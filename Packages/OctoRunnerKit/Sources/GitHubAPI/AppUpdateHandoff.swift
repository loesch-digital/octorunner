import AppKit
import CoreModels
import Foundation
import OSLog

public enum AppUpdateNotice: String, Codable, Sendable, Error {
    case inProgress, restoredPreviousVersion, installationFailed, recoveryRequired
}

public struct StagedAppUpdate: Codable, Sendable {
    private static let stagingPrefix = ".octorunner-update-"
    let directory: URL
    let candidate: URL
    let installed: URL
    let version: String

    var manifest: URL { directory.appending(path: "install.json") }
    var approval: URL { directory.appending(path: "approved") }
    var receipt: URL { directory.appending(path: "started") }

    static func makeStagingDirectory(beside installed: URL) throws -> URL {
        let directory = installed.resolvingSymlinksInPath().deletingLastPathComponent().appending(
            path: stagingPrefix + UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        return directory
    }

    func hasExpectedLayout(beside app: URL) -> Bool {
        let root = directory.standardizedFileURL
        let parent = app.resolvingSymlinksInPath().deletingLastPathComponent()
        let candidateParent = candidate.deletingLastPathComponent()
        let name = root.lastPathComponent
        guard installed.path == app.resolvingSymlinksInPath().path,
              root.deletingLastPathComponent().path == parent.path,
              root.resolvingSymlinksInPath().path == root.path,
              name.hasPrefix(Self.stagingPrefix),
              UUID(uuidString: String(name.dropFirst(Self.stagingPrefix.count))) != nil,
              candidate.lastPathComponent == "OctoRunner.app",
              candidateParent.deletingLastPathComponent().path == root.path,
              UUID(uuidString: candidateParent.lastPathComponent) != nil,
              candidate.resolvingSymlinksInPath().path == candidate.path,
              let attributes = try? FileManager.default.attributesOfItem(atPath: root.path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              attributes[.ownerAccountID] as? UInt32 == geteuid(),
              attributes[.posixPermissions] as? Int == 0o700
        else { return false }
        return true
    }

    public func discard() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
public enum AppUpdateHandoff {
    private static let installArgument = "--octorunner-install-update"
    private static let startupArgument = "--octorunner-confirm-update"
    private static let log = Logger(subsystem: "io.octorunner.macos", category: "AppUpdate")
    private static var pending: StagedAppUpdate?
    private static var storeLease: AppUpdateStoreLease?
    private static var candidateLease: AppUpdateStoreLease?
    private static let noticeFile = AppUpdateJournal.directory.appending(path: "result.json")

    public static var isUpdatePending: Bool { pending != nil }

    public static func schedule(_ update: StagedAppUpdate) throws {
        guard pending == nil else {
            throw AppUpdateError.couldNotReplace
        }
        pending = update
    }

    /// Starts the helper only once the user approves quitting.
    public static func approvePending() throws {
        guard let update = pending else { return }
        guard update.hasExpectedLayout(beside: Bundle.main.bundleURL), let executable = Bundle.main.executableURL
        else { throw AppUpdateError.couldNotReplace }
        try JSONEncoder().encode(update).write(to: update.manifest, options: .atomic)
        try Data().write(to: update.approval, options: .atomic)
        let helper = Process()
        helper.executableURL = executable
        helper.arguments = [
            installArgument, String(ProcessInfo.processInfo.processIdentifier), update.manifest.path
        ]
        try helper.run()
        pending = nil
    }

    public static func cancelPending() {
        pending?.discard()
        pending = nil
    }

    public static func runInstallerIfRequested(arguments: [String]) async -> Bool {
        guard arguments.first == installArgument else { return false }
        guard arguments.count == 3, let parentPID = Int32(arguments[1]),
              parentPID > 1, parentPID != ProcessInfo.processInfo.processIdentifier,
              let update = readManifest(arguments[2])
        else { return true }
        await install(update, parentPID: parentPID)
        return true
    }

    public static func isStartupRequest(arguments: [String]) -> Bool {
        arguments.first == startupArgument
    }

    public static func startupUpdate(arguments: [String]) -> StagedAppUpdate? {
        guard arguments.count == 2, isStartupRequest(arguments: arguments),
              let lease = try? AppUpdateStoreLease.authorizeCandidate(
                installerLock: AppUpdateJournal.installerLock, candidateLock: AppUpdateJournal.candidateLock),
              let update = readManifest(arguments[1]), update.version == AppUpdaterActor.currentBundleVersion,
              FileManager.default.fileExists(atPath: update.approval.path),
              activeJournal?.update.manifest == update.manifest
        else { return nil }
        candidateLease = lease
        return update
    }

    public static func confirmStartup(_ update: StagedAppUpdate) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        try Data(String(pid).utf8).write(to: update.receipt, options: .atomic)
    }

    /// A regular app holds a shared lease for as long as it can use SwiftData.
    public static func allowRegularStartup() async throws -> Bool {
        do {
            guard let lease = try AppUpdateJournal.lease(exclusive: false) else {
                throw AppUpdateNotice.inProgress
            }
            if !FileManager.default.fileExists(atPath: AppUpdateJournal.file.path) {
                storeLease = lease
                return true
            }
        }
        // The shared probe must be released before recovery requests the exclusive lease.
        try await recoverInterruptedUpdate()
        return false
    }

    public static func takeStartupNotice() -> AppUpdateNotice? {
        guard let data = try? Data(contentsOf: noticeFile),
              let notice = try? JSONDecoder().decode(AppUpdateNotice.self, from: data)
        else { return nil }
        do { try FileManager.default.removeItem(at: noticeFile) }
        catch { return nil }
        return notice
    }

    private static func saveNotice(_ notice: AppUpdateNotice) {
        do { try JSONEncoder().encode(notice).write(to: noticeFile, options: .atomic) }
        catch { log.error("Could not save the update outcome: \(error.localizedDescription, privacy: .private)") }
    }

    public static func completeStartup() async throws {
        try await wait(until: {
            guard let lease = try AppUpdateJournal.lease(exclusive: false),
                  !FileManager.default.fileExists(atPath: AppUpdateJournal.file.path) else { return false }
            storeLease = lease
            candidateLease = nil
            return true
        }, timeout: .seconds(45))
    }

    private static var activeJournal: AppUpdateJournal? {
        guard let data = try? Data(contentsOf: AppUpdateJournal.file),
              let journal = try? JSONDecoder().decode(AppUpdateJournal.self, from: data),
              journal.update.hasExpectedLayout(beside: Bundle.main.bundleURL)
        else { return nil }
        return journal
    }

    private static func recoverInterruptedUpdate() async throws {
        var lease = try AppUpdateJournal.lease(exclusive: true)
        guard lease != nil,
              let recovery = try AppUpdateStoreLease(lock: AppUpdateJournal.candidateLock, exclusive: true)
        else { throw AppUpdateNotice.inProgress }
        defer { withExtendedLifetime(recovery) {} }
        guard let journal = activeJournal, journal.store.hasExpectedLayout(for: OctoRunnerPersistence.defaultStoreURL)
        else { throw AppUpdateNotice.recoveryRequired }
        if AppUpdateArchive.version(of: journal.update.installed) == journal.update.version {
            try AppUpdateArchive.validateSignature(candidate: journal.update.candidate, installed: journal.update.installed)
        }
        try journal.rollback()
        try journal.finish()
        saveNotice(.restoredPreviousVersion)
        lease = nil
        _ = try await open(journal.update.installed, arguments: [])
    }

    private static func otherInstances(_ identifier: String) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
    }

    private static func readManifest(_ path: String) -> StagedAppUpdate? {
        let manifest = URL(filePath: path).standardizedFileURL
        guard let data = try? Data(contentsOf: manifest),
              let update = try? JSONDecoder().decode(StagedAppUpdate.self, from: data),
              update.manifest.path == manifest.path,
              update.hasExpectedLayout(beside: Bundle.main.bundleURL)
        else { return nil }
        return update
    }

    private static func install(_ update: StagedAppUpdate, parentPID: pid_t) async {
        var keepBackup = false
        var restartOriginal = false
        var lease: AppUpdateStoreLease?
        var installer: AppUpdateStoreLease?
        defer {
            if !keepBackup { update.discard() }
            withExtendedLifetime(lease) {}
            withExtendedLifetime(installer) {}
        }
        do {
            let parent = NSRunningApplication(processIdentifier: parentPID)
            try await wait(until: {
                parent?.isTerminated ?? (kill(parentPID, 0) != 0 && errno == ESRCH)
            }, timeout: .seconds(120))
            guard FileManager.default.fileExists(atPath: update.approval.path) else { return }
            lease = try AppUpdateJournal.lease(exclusive: true)
            guard lease != nil else { throw AppUpdateError.couldNotReplace }
            installer = try AppUpdateStoreLease(lock: AppUpdateJournal.installerLock, exclusive: true)
            guard let identifier = Bundle.main.bundleIdentifier, installer != nil,
                  otherInstances(identifier).isEmpty,
                  !FileManager.default.fileExists(atPath: AppUpdateJournal.file.path)
            else { throw AppUpdateError.couldNotReplace }
            restartOriginal = true
            try AppUpdateArchive.validateIdentity(candidate: update.candidate, installed: update.installed, expectedVersion: update.version)
            try AppUpdateArchive.validateSignature(candidate: update.candidate, installed: update.installed)
            let store = try AppUpdateStoreBackup(store: OctoRunnerPersistence.defaultStoreURL)
            let journal = AppUpdateJournal(update: update,
                previousVersion: AppUpdateArchive.version(of: update.installed), store: store)
            do { try journal.save() }
            catch { store.discard(); throw error }
            keepBackup = true
            do {
                try await AppUpdateBundleSwap.install(candidate: update.candidate, at: update.installed,
                    beforeRollback: { try store.restore() }) { url in
                    try await launchAndConfirm(url, update: update)
                }
            } catch AppUpdateError.couldNotReplace {
                try journal.finish()
                keepBackup = false
                throw AppUpdateError.couldNotReplace
            } catch AppUpdateError.couldNotRestore {
                keepBackup = true
                restartOriginal = false
                throw AppUpdateError.couldNotRestore
            } catch AppUpdateError.manualRecoveryRequired {
                keepBackup = true
                restartOriginal = false
                throw AppUpdateError.manualRecoveryRequired
            } catch {
                do {
                    try journal.finish()
                    keepBackup = false
                } catch {
                    keepBackup = true
                    restartOriginal = false
                    throw AppUpdateError.manualRecoveryRequired
                }
                throw AppUpdateError.couldNotStart
            }
            restartOriginal = false
            try journal.finish()
            keepBackup = false
        } catch {
            if restartOriginal {
                saveNotice((error as? AppUpdateError) == .couldNotStart ? .restoredPreviousVersion : .installationFailed)
            }
            lease = nil
            installer = nil
            if restartOriginal { _ = try? await open(update.installed, arguments: []) }
            log.error("Update handoff failed: \(error.localizedDescription, privacy: .private)")
            if keepBackup {
                log.error("Previous app retained under \(update.directory.path, privacy: .private)")
            }
        }
    }

    private static func launchAndConfirm(_ url: URL, update: StagedAppUpdate) async throws {
        let application = try await open(url, arguments: [startupArgument, update.manifest.path])
        do {
            try await wait(until: {
                if application.isTerminated { throw AppUpdateError.couldNotStart }
                let receipt = try? String(contentsOf: update.receipt, encoding: .utf8)
                return receipt == String(application.processIdentifier)
            }, timeout: .seconds(30))
        } catch {
            if !application.isTerminated {
                _ = application.forceTerminate()
                do { try await wait(until: { application.isTerminated }, timeout: .seconds(5)) }
                catch { throw AppUpdateError.manualRecoveryRequired }
            }
            throw AppUpdateError.couldNotStart
        }
    }

    private static func open(_ url: URL, arguments: [String]) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        configuration.arguments = arguments
        return try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private static func wait(until condition: () throws -> Bool, timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while try !condition() {
            guard clock.now < deadline else { throw AppUpdateError.couldNotStart }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
