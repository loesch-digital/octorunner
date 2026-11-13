import CoreModels
import Foundation
import SwiftData

/// Opt-in recent-history polling follows the app lifetime, not a visible view.
/// SwiftData stays on MainActor; only immutable selections leave for networking.
@MainActor
public final class LocalJobFailureMonitor {
    private let preferences: AppPreferencesStore
    private let notifications: AppNotificationsController
    private let rateBudget: WorkflowHistoryRateBudget
    private let loader: any WorkflowHistoryLoading
    private var task: Task<Void, Never>?
    private var generation = 0
    private var isRefreshing = false
    private var session: WorkflowHistorySelection?
    private var armedAt: Date?
    private var consentRevision: UInt64?
    private var delivered: [String: Date] = [:]

    public init(preferences: AppPreferencesStore, notifications: AppNotificationsController,
                rateBudget: WorkflowHistoryRateBudget,
                loader: any WorkflowHistoryLoading = GitHubWorkflowHistoryLoader()) {
        self.preferences = preferences
        self.notifications = notifications
        self.rateBudget = rateBudget
        self.loader = loader
    }

    isolated deinit { task?.cancel() }

    public func start(container: ModelContainer) {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(in: container.mainContext)
                do { try await Task.sleep(for: .seconds(self.preferences.historyPreferences.validated().refreshIntervalSeconds)) }
                catch { return }
            }
        }
    }

    public func stop() {
        generation += 1
        task?.cancel()
        task = nil
        resetBaseline()
    }

    /// Explicit refresh also serves deterministic tests; the lifecycle loop sets
    /// the configured polling interval. No permission is requested here.
    public func refresh(in context: ModelContext, now: Date = .now) async {
        guard !Task.isCancelled, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let revision = generation
        do {
            guard let sources = try selections(in: context), let first = sources.first else {
                resetBaseline()
                return
            }
            let identity = WorkflowHistorySelection(accountID: first.accountID, keychainAccountKey: first.keychainAccountKey, repository: "")
            if session != identity || consentRevision != preferences.jobNotificationConsentRevision {
                resetBaseline()
                session = identity
                armedAt = now
                consentRevision = preferences.jobNotificationConsentRevision
            }
            let model = WorkflowHistoryViewModel(loader: loader, rateBudget: rateBudget, acceptResponse: { [weak self] in
                self?.isCurrent(sources, revision: revision, in: context) == true
            })
            await model.refreshRepositories(sources, in: context)
            guard isCurrent(sources, revision: revision, in: context), let armedAt else { return }
            // Delayed responses may arrive out of order. Keep independent job IDs
            // for the last 24 hours rather than a timestamp cursor that drops
            // older jobs when a newer completion has already been delivered.
            let cutoff = max(armedAt, now.addingTimeInterval(-86_400))
            delivered = delivered.filter { $0.value >= cutoff }
            let entries = model.entries.filter { $0.accountID == first.accountID }
            var latestAttempts: [String: Int] = [:]
            for entry in entries {
                if let attempt = entry.attempt {
                    latestAttempts[entry.repository + "|\(entry.githubRunID)"] = max(latestAttempts[entry.repository + "|\(entry.githubRunID)"] ?? 0, attempt)
                }
            }
            let repositories = Set(sources.map(\.repository))
            let ordered = entries.sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            for entry in ordered {
                guard isCurrent(sources, revision: revision, in: context) else { return }
                guard entry.recordKind == "job", entry.status == "completed",
                      entry.conclusion == "failure" || entry.conclusion == "timed_out",
                      let jobID = entry.githubJobID, jobID > 0, let attempt = entry.attempt,
                      latestAttempts[entry.repository + "|\(entry.githubRunID)"] == attempt,
                      repositories.contains(entry.repository), let completed = entry.completedAt,
                      let observed = entry.observedAt, observed <= now.addingTimeInterval(5),
                      completed >= cutoff, completed <= now, completed <= observed.addingTimeInterval(5) else { continue }
                let eventID = "local-job-failure|\(first.accountID)|\(entry.repository)|\(entry.githubRunID)|\(attempt)|\(jobID)"
                guard delivered[eventID] == nil else { continue }
                // Refetch local identities after suspension and before each alert.
                // Remote names and free-form workflow output never prove locality.
                let locals = try context.fetch(FetchDescriptor<RunnerEntity>()).filter { matches($0, entry: entry) }
                guard locals.count == 1, let name = locals.first?.name else { continue }
                let locale = preferences.language.locale
                let event = AppNotificationEvent(id: eventID, kind: .jobFailure,
                    title: AppLocalization.string("Local workflow job failed", locale: locale),
                    message: String(format: AppLocalization.string("A workflow job failed on %@ in %@.", locale: locale), locale: locale, name, entry.repository))
                let published = await notifications.publish(event)
                guard isCurrent(sources, revision: revision, in: context) else { return }
                guard published else { return } // Retry on the next poll, without advancing past a failed delivery.
                delivered[eventID] = completed
            }
        } catch is CancellationError { return }
        catch {
            // History networking exposes typed errors through its own UI. A local
            // read failure is not evidence of a failed workflow or a runner crash.
            return
        }
    }

    private func resetBaseline() {
        session = nil
        armedAt = nil
        consentRevision = nil
        delivered = [:]
    }

    private func isCurrent(_ sources: [WorkflowHistorySelection], revision: Int, in context: ModelContext) -> Bool {
        guard !Task.isCancelled, generation == revision,
              consentRevision == preferences.jobNotificationConsentRevision else { return false }
        return (try? selections(in: context)) == sources
    }

    private func selections(in context: ModelContext) throws -> [WorkflowHistorySelection]? {
        guard preferences.notificationPolicy.enabled, preferences.notificationPolicy.jobFailure else { return nil }
        let accounts = try context.fetch(FetchDescriptor<GitHubAccountEntity>(predicate: #Predicate { $0.isActive }))
        guard accounts.count == 1, let account = accounts.first,
              account.githubUserId > 0, !account.keychainAccountKey.isEmpty else { return nil }
        let runners = try context.fetch(FetchDescriptor<RunnerEntity>())
        guard runners.contains(where: { ($0.githubRunnerId ?? 0) > 0 && $0.scopeType != .personalMultiRepo }) else { return nil }
        let managed = runners.compactMap { runner -> String? in
            guard runner.scopeType == .repository else { return nil }
            return GitHubRepositorySlug(input: runner.scopeUrlString)?.rawValue
        }
        let added = preferences.historyPreferences.validated().additionalRepositoriesByAccount[String(account.githubUserId)] ?? []
        let sources = Array(Set(managed + added)).sorted().map {
            WorkflowHistorySelection(accountID: account.githubUserId, keychainAccountKey: account.keychainAccountKey, repository: $0)
        }
        return sources.isEmpty ? nil : sources
    }

    private func matches(_ runner: RunnerEntity, entry: WorkflowHistoryEntry) -> Bool {
        guard let id = runner.githubRunnerId, id > 0, entry.runnerID == id else { return false }
        switch runner.scopeType {
        case .repository: return GitHubRepositorySlug(input: runner.scopeUrlString)?.rawValue == entry.repository
        case .organization:
            guard let url = URLComponents(string: runner.scopeUrlString), url.scheme == "https", url.host?.lowercased() == "github.com",
                  url.port == nil || url.port == 443, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  !url.percentEncodedPath.contains("%") else { return false }
            let parts = url.path.split(separator: "/")
            guard parts.count == 1, let owner = parts.first,
                  url.percentEncodedPath == "/\(owner)" || url.percentEncodedPath == "/\(owner)/" else { return false }
            return owner.lowercased() == entry.repository.split(separator: "/").first?.lowercased()
        case .personalMultiRepo: return false // Requires the consistent identity model from Step 6.
        }
    }
}
