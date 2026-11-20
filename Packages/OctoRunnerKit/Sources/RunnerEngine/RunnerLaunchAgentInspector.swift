import CoreModels
import Darwin
import Foundation

public struct RunnerLaunchAgentTarget: Sendable, Hashable {
    public let name: String
    public let rootDirectory: URL
    public let label: String

    public init(name: String, rootDirectory: URL, label: String) {
        self.name = name
        self.rootDirectory = rootDirectory
        self.label = label
    }
}

public enum RunnerLaunchAgentDefinition: Sendable, Equatable {
    case missing, invalid, unverified, verified
}

public struct RunnerLaunchAgentDiagnostic: Sendable, Equatable {
    public let definition: RunnerLaunchAgentDefinition
    public let xml: String?
}

public enum RunnerLaunchAgentRuntime: Sendable, Equatable {
    case unloaded, loaded, unverified
    case running(pid: Int32, startedAt: Date?)
}

/// Reads only the expected, user-owned definition under Library/LaunchAgents.
public actor RunnerLaunchAgentInspector {
    typealias Launchctl = @Sendable ([String]) async throws -> (status: Int32, output: String)

    private let managedRoot: URL
    private let launchAgentsDirectory: URL
    private let stagingRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
    private let launchctl: Launchctl
    private let supervisor: RunnerSupervisorActor
    private let hasAnotherListener: @Sendable (URL) async throws -> Bool
    private let maximumDefinitionBytes = 64 * 1024
    private var loadingLabels: Set<String> = []

    public init(supervisor: RunnerSupervisorActor, hasAnotherListener: @escaping @Sendable (URL) async throws -> Bool) {
        self.init(managedRoot: nil, launchAgentsDirectory: nil, launchctl: Self.runLaunchctl,
            supervisor: supervisor, hasAnotherListener: hasAnotherListener)
    }

    init(managedRoot: URL?, launchAgentsDirectory: URL?, launchctl: @escaping Launchctl = RunnerLaunchAgentInspector.runLaunchctl,
         supervisor: RunnerSupervisorActor = RunnerSupervisorActor(),
         hasAnotherListener: @escaping @Sendable (URL) async throws -> Bool = { _ in false }) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.managedRoot = managedRoot ?? home.appending(path: "Library/Application Support/io.octorunner.macos/runners")
        self.launchAgentsDirectory = launchAgentsDirectory ?? home.appending(path: "Library/LaunchAgents")
        self.launchctl = launchctl
        self.supervisor = supervisor
        self.hasAnotherListener = hasAnotherListener
    }

    /// Loads the verified installed definition only when launchd has no running
    /// or loaded instance. Bootstrap rejects a concurrently registered label.
    public func loadDefinition(_ target: RunnerLaunchAgentTarget) async throws {
        guard loadingLabels.insert(target.label).inserted else { throw RunnerSupervisionError.operationInProgress }
        defer { loadingLabels.remove(target.label) }
        let definition = try inspect(target)
        guard definition.definition == .verified else { throw RunnerSupervisionError.notManaged }
        let reservation = await supervisor.reserveIdleDirectories(roots: [target.rootDirectory])
        guard !reservation.isEmpty else { throw RunnerSupervisionError.operationInProgress }
        do {
            try await bootstrap(target, definition: definition)
        } catch {
            await supervisor.releaseDirectories(paths: reservation)
            throw error
        }
        await supervisor.releaseDirectories(paths: reservation)
    }

    private func bootstrap(_ target: RunnerLaunchAgentTarget, definition: RunnerLaunchAgentDiagnostic) async throws {
        guard try await runtime(target) == .unloaded else { throw RunnerSupervisionError.operationInProgress }
        guard try await !hasAnotherListener(target.rootDirectory) else { throw RunnerSupervisionError.operationInProgress }
        try Task.checkCancellation()
        let root = target.rootDirectory.standardizedFileURL
        guard let xml = definition.xml, try inspect(target) == definition,
              Self.isOwnedFile(root.appending(path: "run.sh"), type: S_IFREG),
              Self.isOwnedFile(root.appending(path: "_diag"), type: S_IFDIR) else {
            throw RunnerSupervisionError.notManaged
        }

        // launchd reads a pathname itself. Hand over the verified bytes from a
        // private directory so replacing the installed plist cannot change them.
        let directory = stagingRoot.appending(path: Self.stagingPrefix + UUID().uuidString, directoryHint: .isDirectory)
        guard mkdir(directory.path, 0o700) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: target.label + ".plist")
        try Data(xml.utf8).write(to: path, options: .withoutOverwriting)
        try Task.checkCancellation()
        let command = launchctl
        // Once dispatched, wait for launchd's answer even if the caller closes
        // the view. The staging file stays alive until the command exits.
        let reply = try await Task { try await command(["bootstrap", "gui/\(getuid())", path.path]) }.value
        guard reply.status == 0 else {
            throw RunnerEngineError.launchAgentRegistrationFailed(reply.status, "The service could not be loaded.")
        }
    }

    public func runtime(_ target: RunnerLaunchAgentTarget) async throws -> RunnerLaunchAgentRuntime {
        guard try inspect(target).definition == .verified else { return .unverified }
        let identifier = "gui/\(getuid())/\(target.label)"
        let response = try await launchctl(["print", identifier])
        try Task.checkCancellation()
        if response.status == 113 { return .unloaded }
        guard response.status == 0 else { throw CocoaError(.fileReadUnknown) }
        guard let registration = Self.parseRegistration(response.output, identifier: identifier),
              matchesServicePath(registration.path, label: target.label),
              Self.matchesWorkingDirectory(registration.root, root: target.rootDirectory.standardizedFileURL),
              registration.arguments == ["/bin/bash", target.rootDirectory.appending(path: "run.sh").path] else {
            return .unverified
        }
        if let pid = registration.pid {
            return .running(pid: pid, startedAt: Self.startedAt(pid: pid))
        }
        return registration.state == "not running" ? .loaded : .unverified
    }

    private static let stagingPrefix = "OctoRunner-LaunchAgent-"

    private func matchesServicePath(_ path: String, label: String) -> Bool {
        let file = URL(filePath: path)
        let parent = file.deletingLastPathComponent()
        let folder = parent.lastPathComponent
        guard file.lastPathComponent == label + ".plist" else { return false }
        if parent.path == launchAgentsDirectory.path { return true }
        // launchd continues to report the bootstrap source after processing it.
        return parent.deletingLastPathComponent().path == stagingRoot.path
            && folder.hasPrefix(Self.stagingPrefix)
            && UUID(uuidString: String(folder.dropFirst(Self.stagingPrefix.count))) != nil
    }

    public func inspect(_ target: RunnerLaunchAgentTarget) throws -> RunnerLaunchAgentDiagnostic {
        try Task.checkCancellation()
        let root = target.rootDirectory.standardizedFileURL
        guard target.rootDirectory.isFileURL,
              target.label == RunnerServiceLabel.forRunner(named: target.name),
              Self.validLabel(target.label),
              root.deletingLastPathComponent().path == managedRoot.standardizedFileURL.path,
              Self.isOwnedFile(managedRoot, type: S_IFDIR),
              Self.isOwnedFile(root, type: S_IFDIR) else {
            return .init(definition: .unverified, xml: nil)
        }
        var directory = stat()
        if lstat(launchAgentsDirectory.path, &directory) == -1, errno == ENOENT {
            return .init(definition: .missing, xml: nil)
        }
        guard directory.st_mode & S_IFMT == S_IFDIR else {
            return .init(definition: .unverified, xml: nil)
        }
        let plistURL = launchAgentsDirectory.appending(path: target.label + ".plist")
        let descriptor = open(plistURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            return .init(definition: errno == ENOENT ? .missing : .unverified, xml: nil)
        }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_size <= maximumDefinitionBytes else {
            return .init(definition: .unverified, xml: nil)
        }
        let data = try file.read(upToCount: maximumDefinitionBytes + 1) ?? Data()
        try Task.checkCancellation()
        guard data.count <= maximumDefinitionBytes else { return .init(definition: .unverified, xml: nil) }
        guard let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            return .init(definition: .invalid, xml: nil)
        }
        guard let definition = raw as? [String: Any],
              Self.matchesGeneratedDefinition(definition, target: target, root: root) else {
            return .init(definition: .unverified, xml: nil)
        }
        let xmlData = try PropertyListSerialization.data(fromPropertyList: definition, format: .xml, options: 0)
        return .init(definition: .verified, xml: String(decoding: xmlData, as: UTF8.self))
    }

    private static func validLabel(_ label: String) -> Bool {
        label.hasPrefix("io.octorunner.agent.") && label.count > "io.octorunner.agent.".count
            && !label.contains("/") && !label.contains("\\")
            && label.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private static func isOwnedFile(_ url: URL, type: mode_t) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == type && info.st_uid == getuid()
    }

    private static func matchesWorkingDirectory(_ path: String?, root: URL) -> Bool {
        path == root.path || path == root.path + "/"
    }

    private static func matchesGeneratedDefinition(_ plist: [String: Any], target: RunnerLaunchAgentTarget, root: URL) -> Bool {
        let commonKeys: Set<String> = ["Label", "ProgramArguments", "WorkingDirectory", "RunAtLoad",
            "KeepAlive", "EnvironmentVariables", "StandardOutPath", "StandardErrorPath"]
        guard plist["Label"] as? String == target.label,
              plist["ProgramArguments"] as? [String] == ["/bin/bash", root.appending(path: "run.sh").path],
              matchesWorkingDirectory(plist["WorkingDirectory"] as? String, root: root),
              plist["StandardOutPath"] as? String == root.appending(path: "_diag/launchd.stdout.log").path,
              plist["StandardErrorPath"] as? String == root.appending(path: "_diag/launchd.stderr.log").path,
              plist["RunAtLoad"] as? Bool == true,
              let environment = plist["EnvironmentVariables"] as? [String: String],
              environment["LANG"] == "en_US.UTF-8",
              let path = environment["PATH"], !path.isEmpty,
              path.split(separator: ":", omittingEmptySubsequences: false).allSatisfy({
                  $0.hasPrefix("/") && !$0.contains(where: { $0.isNewline || $0 == "\0" })
              }) else { return false }
        // The earliest released generator always used these fixed values and
        // omitted both SHELL and ThrottleInterval.
        let keys = Set(plist.keys)
        if keys == commonKeys {
            return Set(environment.keys) == ["PATH", "LANG"]
                && path == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                && plist["KeepAlive"] as? Bool == true
        }
        guard keys == commonKeys.union(["ThrottleInterval"]),
              let interval = plist["ThrottleInterval"] as? Int, (1...300).contains(interval),
              Set(environment.keys) == ["PATH", "SHELL", "LANG"],
              let shell = environment["SHELL"], RunnerShell(rawValue: shell) != nil else { return false }
        return plist["KeepAlive"] is Bool || plist["KeepAlive"] as? [String: Bool] == ["SuccessfulExit": false]
    }

    private struct Registration {
        let path: String
        let root: String
        let state: String
        let arguments: [String]
        let pid: Int32?
    }

    private static func parseRegistration(_ output: String, identifier: String) -> Registration? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "\(identifier) = {",
              let start = lines.firstIndex(of: "\targuments = {"),
              let end = lines[(start + 1)...].firstIndex(of: "\t}") else { return nil }
        let rows = lines.filter { $0.hasPrefix("\t") && !$0.hasPrefix("\t\t") }
        func field(_ key: String) -> String? {
            let prefix = "\t\(key) = "
            let matches = rows.filter { $0.hasPrefix(prefix) }
            guard matches.count == 1, let match = matches.first else { return nil }
            return String(match.dropFirst(prefix.count))
        }
        guard field("type") == "LaunchAgent", field("program") == "/bin/bash",
              let path = field("path"), let root = field("working directory"), let state = field("state") else { return nil }
        let arguments = lines[(start + 1)..<end].map { String($0.dropFirst(2)) }
        if let value = field("pid") {
            guard let pid = Int32(value), pid > 0 else { return nil }
            return Registration(path: path, root: root, state: state, arguments: arguments, pid: pid)
        }
        guard !rows.contains(where: { $0.hasPrefix("\tpid = ") }) else { return nil }
        return Registration(path: path, root: root, state: state, arguments: arguments, pid: nil)
    }

    private static func startedAt(pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_uid == getuid(), info.pbi_start_tvsec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }

    private static func runLaunchctl(_ arguments: [String]) async throws -> (status: Int32, output: String) {
        guard let temporaryOutput = tmpfile() else { throw CocoaError(.fileWriteUnknown) }
        defer { fclose(temporaryOutput) }
        let output = FileHandle(fileDescriptor: fileno(temporaryOutput), closeOnDealloc: false)
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let status = try await ConfigurationProcessRunner.run(process)
        try output.seek(toOffset: 0)
        let limit = 256 * 1024
        let data = try output.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        return (status, String(decoding: data, as: UTF8.self))
    }
}
