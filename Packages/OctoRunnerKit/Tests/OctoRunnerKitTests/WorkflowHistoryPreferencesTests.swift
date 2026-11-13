import CoreModels
import Foundation
import Testing

@MainActor
struct WorkflowHistoryPreferencesTests {
    @Test("History repository choices and explicit duration targets persist without crossing accounts")
    func persistence() throws {
        let suite = "octorunner-history-preferences-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppPreferencesStore(defaults: defaults)
        #expect(store.historyPreferences.durationSLATargetSeconds == nil)
        #expect(store.historyPreferences.refreshIntervalSeconds == 60)
        store.historyPreferences.additionalRepositoriesByAccount = ["7": ["EXAMPLE/Repo", "example/repo", "example/second"], "8": ["other/private"]]
        store.historyPreferences.durationSLATargetSeconds = 300
        let restored = AppPreferencesStore(defaults: defaults).historyPreferences
        #expect(restored.additionalRepositoriesByAccount["7"] == ["example/repo", "example/second"])
        #expect(restored.additionalRepositoriesByAccount["8"] == ["other/private"])
        #expect(restored.durationSLATargetSeconds == 300)
    }

    @Test("Invalid history preferences never add unsafe sources or invent a duration target")
    func validation() throws {
        let suite = "octorunner-history-invalid-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppPreferencesStore(defaults: defaults)
        store.historyPreferences.additionalRepositoriesByAccount = ["7": ["owner/repo", "../repo", "https://evil.example/repo", "owner/repo?token=synthetic"], "invalid": ["other/repo"]]
        store.historyPreferences.durationSLATargetSeconds = -1
        store.historyPreferences.refreshIntervalSeconds = 1
        #expect(store.historyPreferences.additionalRepositoriesByAccount == ["7": ["owner/repo"]])
        #expect(store.historyPreferences.durationSLATargetSeconds == nil)
        #expect(store.historyPreferences.refreshIntervalSeconds == 60)
        defaults.set(Data("broken".utf8), forKey: "preferences.historyPreferences")
        #expect(AppPreferencesStore(defaults: defaults).historyPreferences == WorkflowHistoryPreferences())
    }

    @Test("Repository input accepts GitHub scopes and slugs while rejecting credentials, queries and other hosts")
    func repositoryInput() {
        #expect(GitHubRepositorySlug(input: " OWNER/Repository ")?.rawValue == "owner/repository")
        #expect(GitHubRepositorySlug(input: "https://github.com/OWNER/Repository/")?.rawValue == "owner/repository")
        for input in ["https://evil.example/owner/repo", "https://token@github.com/owner/repo", "https://github.com/owner/repo?token=synthetic", "https://github.com/owner/repo/issues", "http://github.com/owner/repo", "owner", "../repo", "owner/.."] {
            #expect(GitHubRepositorySlug(input: input) == nil)
        }
    }
}
