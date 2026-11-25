import CoreModels
import DesignSystem
import SwiftData
import SwiftUI
import SyncKit

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
    @State private var selectedRun: WorkflowHistoryEntry?
    @State private var isShowingSources = false
    private let observedRepositoryChanged: (String) -> Void
    private let rateBudget: WorkflowHistoryRateBudget

    public init(rateBudget: WorkflowHistoryRateBudget = WorkflowHistoryRateBudget()) {
        self.init(rateBudget: rateBudget, initialRun: nil, showsRunning: false)
    }

    init(rateBudget: WorkflowHistoryRateBudget, initialRun: WorkflowHistoryEntry?, showsRunning: Bool, observedRepositoryChanged: @escaping (String) -> Void = { _ in }) {
        self.observedRepositoryChanged = observedRepositoryChanged
        self.rateBudget = rateBudget
        _model = State(initialValue: WorkflowHistoryViewModel(rateBudget: rateBudget))
        _selectedRun = State(initialValue: initialRun)
        _filter = State(initialValue: WorkflowHistoryFilter(status: showsRunning ? .running : .all))
    }

    public var body: some View {
        @Bindable var preferences = preferences
        let request = request
        VStack(spacing: 0) {
            HStack {
                Button { isShowingSources = true } label: {
                    Label { Text("History sources", bundle: .module) } icon: { Image(systemName: "folder") }
                }
                .accessibilityHint(Text("Manage additional repository sources for the active account", bundle: .module))
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(OctoTheme.surface)
            WorkflowHistoryContent(entries: model.entries.filter { $0.accountID == request.account?.accountID }, repositories: repositoryChoices, repository: $selectedRepository,
                filter: $filter, durationTarget: $preferences.historyPreferences.durationSLATargetSeconds,
                isLoading: isRefreshing, errorMessage: errorMessage(account: request.account), lastRefresh: model.lastRefresh,
                rateLimitRemaining: model.rateLimit?.remaining, canLoadOlder: request.sources.count == 1 && !selectedRepository.isEmpty && model.nextPage != nil,
                refresh: { loadOlderSource = nil; refreshTicket = UUID() },
                loadOlder: { loadOlderSource = request.sources.first; refreshTicket = UUID() },
                observationMaxAge: preferences.historyPreferences.observationMaxAge,
                openDetails: { selectedRun = $0 })
        }
        .onChange(of: request.selectedRepository, initial: true) { observedRepositoryChanged(request.selectedRepository) }
        .onChange(of: selectedRepository) { repositoryAccountID = accountSelection?.accountID }
        .onChange(of: accountSelection?.accountID) {
            selectedRun = nil
            selectedRepository = ""
            repositoryAccountID = accountSelection?.accountID
            filter = WorkflowHistoryFilter()
            repositoryInput = ""
            sourceInputError = false
        }
        .sheet(isPresented: $isShowingSources) {
            sourceControls(account: accountSelection)
        }
        .sheet(item: $selectedRun) { run in
            if let account = activeAccount,
               let selection = WorkflowRunDetailSelection(entry: run, source: .init(accountID: account.githubUserId,
                keychainAccountKey: account.keychainAccountKey, repository: run.repository)) {
                WorkflowRunDetailView(entry: run, selection: selection, rateBudget: rateBudget,
                    runnerAccount: RunnerSyncAccount(account), runnerConfigurations: runnerConfigurations)
            }
        }
        .task(id: request) { await observe(request) }
        .onDisappear { model.invalidate() }
    }

    private var activeAccount: GitHubAccountEntity? {
        let active = accounts.filter(\.isActive)
        return active.count == 1 ? active.first : nil
    }

    private var accountSelection: WorkflowHistorySelection? {
        activeAccount.map {
            WorkflowHistorySelection(accountID: $0.githubUserId, keychainAccountKey: $0.keychainAccountKey, repository: "")
        }
    }

    private var runnerConfigurations: [UUID: LocalDotRunnerConfig] {
        var configurations: [UUID: LocalDotRunnerConfig] = [:]
        for runner in runners {
            configurations[runner.id] = LocalDotRunnerConfig(runner)
        }
        return configurations
    }

    private var managedRepositories: [String] {
        WorkflowHistorySelection.managedRepositories(for: runners)
    }

    private var configuredRepositories: [String] {
        guard let account = accountSelection else { return [] }
        return WorkflowHistorySelection.configuredRepositories(for: runners, accountID: account.accountID,
            preferences: preferences.historyPreferences).sorted()
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("History sources", bundle: .module).font(.headline)
                    Spacer(minLength: 8)
                    Button { isShowingSources = false } label: { Text("Close", bundle: .module) }
                        .keyboardShortcut(.cancelAction)
                }
                Text("Recent runs refresh while OctoRunner is active. Add the repositories you want to follow for organization runners.", bundle: .module)
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
            }.padding(20)
        }
        .frame(minWidth: 360, idealWidth: 480, minHeight: 180, idealHeight: 240)
        .background(OctoTheme.surface)
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
        let banner = WorkflowHistoryRepositoryFailure.banner(error: model.error,
            failures: model.repositoryFailures, locale: locale)
        if model.error == nil, let deadline = model.retryNotBefore, deadline > .now {
            let pause = AppLocalization.string("GitHub rate limit reached; refresh is paused", locale: locale)
                + " · " + deadline.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(locale))
            return [pause, banner].compactMap { $0 }.joined(separator: "\n")
        }
        return banner
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
        while model.error != .authenticationRequired {
            let delay = max(Double(request.refreshInterval), model.retryNotBefore?.timeIntervalSinceNow ?? 0)
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            isRefreshing = true
            await model.refreshRepositories(request.sources, in: modelContext)
            guard !Task.isCancelled else { return }
            isRefreshing = false
        }
    }
}
