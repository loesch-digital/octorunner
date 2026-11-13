import Foundation
import Observation

@Observable
@MainActor
public final class AppPreferencesStore {
    @ObservationIgnored private let defaults: UserDefaults

    public var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "preferences.language") }
    }
    public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "preferences.launchAtLogin") }
    }
    public var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: "preferences.showInMenuBar") }
    }
    public var hideDockIconWhenClosed: Bool {
        didSet { defaults.set(hideDockIconWhenClosed, forKey: "preferences.hideDockIconWhenClosed") }
    }
    public var updateChannel: String = "stable"
    private var storedMaxConcurrentRunners: Int
    public var maxConcurrentRunners: Int {
        get { storedMaxConcurrentRunners }
        set {
            storedMaxConcurrentRunners = Self.clamp(newValue, to: 1...64)
            defaults.set(storedMaxConcurrentRunners, forKey: "preferences.maxConcurrentRunners")
        }
    }
    public var inheritHostPath: Bool {
        didSet { defaults.set(inheritHostPath, forKey: "preferences.inheritHostPath") }
    }
    public var diskAutoPruningEnabled: Bool {
        get { storagePolicy.pruningMode != .manual }
        set {
            if !newValue { storagePolicy.pruningMode = .manual }
            else if storagePolicy.pruningMode == .manual { storagePolicy.pruningMode = .olderThanDays }
        }
    }
    private var storedPruneWorkspacesOlderThanDays: Int
    public var pruneWorkspacesOlderThanDays: Int {
        get { storedPruneWorkspacesOlderThanDays }
        set {
            storedPruneWorkspacesOlderThanDays = Self.clamp(newValue, to: 1...365)
            defaults.set(storedPruneWorkspacesOlderThanDays, forKey: "preferences.pruneWorkspacesOlderThanDays")
        }
    }
    public var customRunnerDownloadURL: String = ""

    private var storedRuntimePolicy = RunnerRuntimePolicy()
    public var runtimePolicy: RunnerRuntimePolicy {
        get { storedRuntimePolicy }
        set {
            storedRuntimePolicy = newValue.validated()
            persist(storedRuntimePolicy, forKey: "preferences.runtimePolicy")
        }
    }
    private var storedStoragePolicy = StoragePolicy()
    public var storagePolicy: StoragePolicy {
        get { storedStoragePolicy }
        set {
            storedStoragePolicy = newValue.validated()
            persist(storedStoragePolicy, forKey: "preferences.storagePolicy")
        }
    }
    public var notificationPolicy: NotificationPolicy {
        didSet {
            if oldValue.enabled != notificationPolicy.enabled || oldValue.jobFailure != notificationPolicy.jobFailure {
                jobNotificationConsentRevision &+= 1
            }
            persist(notificationPolicy, forKey: "preferences.notificationPolicy")
        }
    }
    /// In-memory revision detects off/on cycles even between background polls.
    public private(set) var jobNotificationConsentRevision: UInt64 = 0
    private var storedHistoryPreferences = WorkflowHistoryPreferences()
    public var historyPreferences: WorkflowHistoryPreferences {
        get { storedHistoryPreferences }
        set {
            storedHistoryPreferences = newValue.validated()
            persist(storedHistoryPreferences, forKey: "preferences.historyPreferences")
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: "preferences.language") ?? "") ?? .system
        launchAtLogin = defaults.object(forKey: "preferences.launchAtLogin") as? Bool ?? false
        showInMenuBar = defaults.object(forKey: "preferences.showInMenuBar") as? Bool ?? true
        hideDockIconWhenClosed = defaults.object(forKey: "preferences.hideDockIconWhenClosed") as? Bool ?? true
        storedMaxConcurrentRunners = Self.clamp(defaults.object(forKey: "preferences.maxConcurrentRunners") as? Int ?? 4, to: 1...64)
        inheritHostPath = defaults.object(forKey: "preferences.inheritHostPath") as? Bool ?? true
        storedPruneWorkspacesOlderThanDays = Self.clamp(defaults.object(forKey: "preferences.pruneWorkspacesOlderThanDays") as? Int ?? 7, to: 1...365)
        storedRuntimePolicy = Self.load(RunnerRuntimePolicy.self, from: defaults, key: "preferences.runtimePolicy")?.validated() ?? RunnerRuntimePolicy()
        storedStoragePolicy = Self.load(StoragePolicy.self, from: defaults, key: "preferences.storagePolicy")?.validated() ?? StoragePolicy()
        notificationPolicy = Self.load(NotificationPolicy.self, from: defaults, key: "preferences.notificationPolicy") ?? NotificationPolicy()
        storedHistoryPreferences = Self.load(WorkflowHistoryPreferences.self, from: defaults, key: "preferences.historyPreferences")?.validated() ?? WorkflowHistoryPreferences()
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, from defaults: UserDefaults, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func persist<Value: Encodable>(_ value: Value, forKey key: String) {
        // Policy values contain no credentials; repository identities are validated before persistence.
        // Keep the previous stored value if a future encoder ever rejects a value.
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
