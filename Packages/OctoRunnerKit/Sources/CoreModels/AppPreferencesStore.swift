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
        didSet { defaults.set(diskAutoPruningEnabled, forKey: "preferences.diskAutoPruningEnabled") }
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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: "preferences.language") ?? "") ?? .system
        launchAtLogin = defaults.object(forKey: "preferences.launchAtLogin") as? Bool ?? false
        showInMenuBar = defaults.object(forKey: "preferences.showInMenuBar") as? Bool ?? true
        hideDockIconWhenClosed = defaults.object(forKey: "preferences.hideDockIconWhenClosed") as? Bool ?? true
        storedMaxConcurrentRunners = Self.clamp(defaults.object(forKey: "preferences.maxConcurrentRunners") as? Int ?? 4, to: 1...64)
        inheritHostPath = defaults.object(forKey: "preferences.inheritHostPath") as? Bool ?? true
        diskAutoPruningEnabled = defaults.object(forKey: "preferences.diskAutoPruningEnabled") as? Bool ?? false
        storedPruneWorkspacesOlderThanDays = Self.clamp(defaults.object(forKey: "preferences.pruneWorkspacesOlderThanDays") as? Int ?? 7, to: 1...365)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
