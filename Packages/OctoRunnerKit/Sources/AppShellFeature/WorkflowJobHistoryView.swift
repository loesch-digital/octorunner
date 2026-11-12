import CoreModels
import DesignSystem
import SwiftData
import SwiftUI

public struct WorkflowJobHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(AppPreferencesStore.self) private var preferences
    @Query(sort: \GitHubAccountEntity.connectedAt, order: .reverse) private var accounts: [GitHubAccountEntity]
    @Query private var runners: [RunnerEntity]
    @State private var model: WorkflowHistoryViewModel
    @State private var filter = WorkflowHistoryFilter()
    @State private var selectedRepository = ""
    @State private var repositoryInput = ""
    @State private var sourceInputError = false
    @State private var refreshTicket = UUID()
    @State private var loadOlderSource: WorkflowHistorySelection?
    @State private var repositoryAccountID: Int64?
    @State private var cacheLoadFailed = false
    @State private var operationID: UUID?
    @State private var isRefreshing = false

    public init(rateBudget: WorkflowHistoryRateBudget = WorkflowHistoryRateBudget()) {
        _model = State(initialValue: WorkflowHistoryViewModel(rateBudget: rateBudget))
    }

    public var body: some View {
        @Bindable var preferences = preferences
        let request = request
        VStack(spacing: 0) {
            sourceControls(account: request.account)
            WorkflowHistoryContent(entries: model.entries.filter { $0.accountID == request.account?.accountID }, repositories: repositoryChoices, repository: $selectedRepository,
                filter: $filter, durationTarget: $preferences.historyPreferences.durationSLATargetSeconds,
                isLoading: isRefreshing, errorMessage: errorMessage(account: request.account), lastRefresh: model.lastRefresh,
                rateLimitRemaining: model.rateLimit?.remaining, canLoadOlder: request.sources.count == 1 && !selectedRepository.isEmpty && model.nextPage != nil,
                refresh: { loadOlderSource = nil; refreshTicket = UUID() },
                loadOlder: { loadOlderSource = request.sources.first; refreshTicket = UUID() })
        }
        .onChange(of: selectedRepository) { repositoryAccountID = accountSelection?.accountID }
        .onChange(of: accountSelection?.accountID) {
            selectedRepository = ""
            repositoryAccountID = accountSelection?.accountID
            filter = WorkflowHistoryFilter()
            repositoryInput = ""
            sourceInputError = false
        }
        .task(id: request) { await observe(request) }
        .onDisappear { model.invalidate() }
    }

    private var accountSelection: WorkflowHistorySelection? {
        guard let account = accounts.first(where: \.isActive) else { return nil }
        return WorkflowHistorySelection(accountID: account.githubUserId, keychainAccountKey: account.keychainAccountKey, repository: "")
    }

    private var managedRepositories: [String] {
        Array(Set(runners.compactMap { GitHubRepositorySlug(input: $0.scopeUrlString)?.rawValue })).sorted()
    }

    private var configuredRepositories: [String] {
        guard let account = accountSelection else { return [] }
        let added = preferences.historyPreferences.additionalRepositoriesByAccount[String(account.accountID)] ?? []
        return Array(Set(managedRepositories + added)).sorted()
    }

    private var repositoryChoices: [String] {
        Array(Set(configuredRepositories + model.entries.map(\.repository))).sorted()
    }

    private var request: WorkflowHistoryRequest {
        let account = accountSelection
        let scopedRepository = repositoryAccountID == account?.accountID ? selectedRepository : ""
        let sources = scopedRepository.isEmpty ? configuredRepositories : [scopedRepository]
        return WorkflowHistoryRequest(account: account, sources: account.map { account in sources.map {
            WorkflowHistorySelection(accountID: account.accountID, keychainAccountKey: account.keychainAccountKey, repository: $0)
        }} ?? [], selectedRepository: scopedRepository, isActive: scenePhase == .active,
            refreshInterval: preferences.historyPreferences.refreshIntervalSeconds, ticket: refreshTicket)
    }

    private func sourceControls(account: WorkflowHistorySelection?) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent runs refresh while this view is active. Add repositories for organization runners explicitly.", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField(text: $repositoryInput) { Text("owner/repository or GitHub URL", bundle: .module) }
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(Text("Additional history repository", bundle: .module))
                        .accessibilityHint(Text("Enter a repository belonging to the active GitHub account", bundle: .module))
                        .onSubmit { addRepository(account: account) }
                    Button { addRepository(account: account) } label: { Text("Add", bundle: .module) }
                        .disabled(account == nil)
                        .accessibilityLabel(Text("Add history repository", bundle: .module))
                        .accessibilityHint(Text("Saves this repository for the active account and loads recent runs", bundle: .module))
                }
                if sourceInputError { Text("Enter a valid GitHub owner/repository", bundle: .module).font(.caption).foregroundStyle(OctoTheme.errorRed) }
                if let account {
                    let added = preferences.historyPreferences.additionalRepositoriesByAccount[String(account.accountID)] ?? []
                    if !added.isEmpty {
                        Menu {
                            ForEach(added, id: \.self) { repository in
                                Button(repository, role: .destructive) { removeRepository(repository, accountID: account.accountID) }
                            }
                        } label: { Text("Remove additional repository", bundle: .module) }
                        .accessibilityLabel(Text("Remove additional repository", bundle: .module))
                        .accessibilityHint(Text("Stops including this source in automatic refresh; saved history remains", bundle: .module))
                    }
                }
            }.padding(.top, 8)
        } label: { Text("History sources", bundle: .module) }
        .accessibilityLabel(Text("History sources", bundle: .module))
        .accessibilityHint(Text("Manage additional repository sources for the active account", bundle: .module))
        .padding(16).background(OctoTheme.surface)
    }

    private func addRepository(account: WorkflowHistorySelection?) {
        guard let account, let slug = GitHubRepositorySlug(input: repositoryInput) else { sourceInputError = true; return }
        let key = String(account.accountID)
        var history = preferences.historyPreferences
        history.additionalRepositoriesByAccount[key, default: []].append(slug.rawValue)
        preferences.historyPreferences = history
        repositoryInput = ""
        sourceInputError = false
        repositoryAccountID = account.accountID
        selectedRepository = slug.rawValue
        refreshTicket = UUID()
    }

    private func removeRepository(_ repository: String, accountID: Int64) {
        var history = preferences.historyPreferences
        history.additionalRepositoriesByAccount[String(accountID)]?.removeAll { $0 == repository }
        preferences.historyPreferences = history
        if selectedRepository == repository { selectedRepository = "" }
        refreshTicket = UUID()
    }

    private func errorMessage(account: WorkflowHistorySelection?) -> String? {
        guard account != nil else { return AppLocalization.string("Connect a GitHub account to load workflow history", locale: locale) }
        if cacheLoadFailed { return AppLocalization.string("History could not be loaded; saved observations remain available", locale: locale) }
        let key: String.LocalizationValue
        switch model.error {
        case .authenticationRequired: key = "Reconnect this GitHub account to load history"
        case .permissionDenied: key = "This token cannot read Actions for the selected repository"
        case .rateLimited: key = "GitHub rate limit reached; refresh is paused"
        case .tooManyPages: key = "Job details exceeded the safe pagination limit"
        case .unavailable: key = "History could not be loaded; saved observations remain available"
        case nil:
            if !model.repositoryFailures.isEmpty {
                return AppLocalization.string("Some repositories could not be refreshed", locale: locale) + ": " + model.repositoryFailures.map(\.repository).joined(separator: ", ")
            }
            if let deadline = model.retryNotBefore, deadline > .now {
                return AppLocalization.string("GitHub rate limit reached; refresh is paused", locale: locale) + " · " + deadline.formatted(date: .omitted, time: .standard)
            }
            return nil
        }
        return AppLocalization.string(key, locale: locale)
    }

    private func observe(_ request: WorkflowHistoryRequest) async {
        guard !Task.isCancelled else { return }
        model.invalidate()
        guard request.isActive else { isRefreshing = false; return }
        let id = UUID()
        operationID = id
        isRefreshing = true
        defer { if operationID == id { isRefreshing = false } }
        let older = request.sources.count == 1 && loadOlderSource == request.sources.first
        loadOlderSource = nil
        cacheLoadFailed = false
        guard !request.sources.isEmpty else {
            do { try model.select(request.account, in: modelContext) } catch { cacheLoadFailed = true }
            return
        }
        if older { await model.load(in: modelContext) }
        else { await model.refreshRepositories(request.sources, in: modelContext) }
        guard !Task.isCancelled else { return }
        isRefreshing = false
        while model.error == nil, model.repositoryFailures.isEmpty, (model.retryNotBefore ?? .distantPast) <= .now {
            do { try await Task.sleep(for: .seconds(request.refreshInterval)) } catch { return }
            guard !Task.isCancelled else { return }
            isRefreshing = true
            await model.refreshRepositories(request.sources, in: modelContext)
            guard !Task.isCancelled else { return }
            isRefreshing = false
        }
    }
}
