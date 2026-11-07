import Foundation
import Observation

@Observable
@MainActor
public final class AppPreferencesStore {
    public var language: AppLanguage = .system
    public var launchAtLogin: Bool = true
    public var showInMenuBar: Bool = true
    public var hideDockIconWhenClosed: Bool = true
    public var updateChannel: String = "stable"
    public var maxConcurrentRunners: Int = 4
    public var inheritHostPath: Bool = true
    public var diskAutoPruningEnabled: Bool = true
    public var pruneWorkspacesOlderThanDays: Int = 7
    public var customRunnerDownloadURL: String = ""

    public init() {}
}
