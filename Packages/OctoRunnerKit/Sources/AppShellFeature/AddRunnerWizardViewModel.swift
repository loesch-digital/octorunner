import CoreModels
import Foundation
import GitHubAPI
import Observation
import RunnerEngine
import SecurityKit
import SwiftData
import SyncKit

@MainActor
@Observable
public final class AddRunnerWizardViewModel {
    struct TargetAccount: Equatable {
        let key: String
        let revision: UUID
    }

    struct OrganizationSelection: Hashable {
        let key: String
        let revision: UUID?
        let scope: URL
    }

    public var selectedScope: RunnerScopeType = .repository {
        didSet {
            if selectedScope != oldValue { manualTargetInput = "" }
        }
    }
    public var repositories: [GitHubRepositorySummaryDTO] = []
    public var organizations: [GitHubOrganizationSummaryDTO] = []
    public var selectedRepositoryFullName: String = ""
    public var selectedRepositoryFullNames: Set<String> = []
    public var selectedOrganizationLogin: String = ""
    public var manualTargetInput: String = ""
    public var selectedRunnerGroupID: Int64?
    public private(set) var organizationGroups: [GitHubRunnerGroupDTO] = []
    private(set) var groupLookup: RunnerGroupInventory?
    @ObservationIgnored private var groupSelection: OrganizationSelection?
    @ObservationIgnored private var groupLoadID: UUID?
    @ObservationIgnored private var targetAccount: TargetAccount?
    @ObservationIgnored private var targetLoadID: UUID?

    public var instanceCount: Int = 2
    public var baseNamePrefix: String = {
        let rawHost = String(ProcessInfo.processInfo.hostName.split(separator: ".").first ?? "mac")
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        if rawHost.isEmpty || rawHost.count > 16 {
            return "mac-runner"
        }
        return rawHost.hasSuffix("-runner") ? rawHost : "\(rawHost)-runner"
    }()

    public var availableDefaultLabels: [String] = [
        "self-hosted",
        "macos",
        "arm64",
        "apple-silicon",
        "xcode-27",
        "ios-simulator"
    ]
    public var selectedLabels: [String] = [
        "self-hosted",
        "macos",
        "arm64",
        "apple-silicon",
        "xcode-27"
    ]
    public var customLabelInput: String = ""
    public var registerLaunchAgent: Bool = true

    public var isLoadingTargets: Bool = false
    public var isProvisioning: Bool = false
    public private(set) var provisioningCompleted = false
    public var provisioningProgressMessage: RunnerProvisioningProgress?
    public var errorMessage: AppErrorMessage?

    private let provisioningClient: any RunnerTargetLoading
    private let provisionerActor: any RunnerProvisioning
    private let vault: KeychainVaultActor
    private let supervisor: RunnerSupervisorActor
    private let runnerSync: GitHubRunnerSyncActor

    public init(
        provisioningClient: any RunnerTargetLoading = GitHubRunnerProvisioningClient(),
        provisionerActor: any RunnerProvisioning = RunnerProvisionerActor(),
        vault: KeychainVaultActor = KeychainVaultActor(),
        supervisor: RunnerSupervisorActor = RunnerSupervisorActor(),
        runnerSync: GitHubRunnerSyncActor = GitHubRunnerSyncActor()
    ) {
        self.provisioningClient = provisioningClient
        self.provisionerActor = provisionerActor
        self.vault = vault
        self.supervisor = supervisor
        self.runnerSync = runnerSync
    }

    public var previewInstanceNames: [String] {
        let cleanedPrefix = baseNamePrefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
        let prefix = cleanedPrefix.isEmpty ? "mac-runner" : cleanedPrefix
        let clampedCount = max(1, min(8, instanceCount))
        if clampedCount == 1 {
            return ["\(prefix)-1"]
        }
        return (1...clampedCount).map { "\(prefix)-\($0)" }
    }

    public var plannedRunnerCount: Int {
        resolvedTargetSummaries.count * previewInstanceNames.count
    }

    var plannedNameExamples: [String] {
        let targets = resolvedTargetSummaries
        let names = previewInstanceNames
        guard targets.count > 1 else { return names }
        return targets.prefix(2).flatMap { target in
            Self.instanceNames(names, owner: target.owner, repository: target.repo).prefix(3)
        }
    }

    private static func instanceNames(_ names: [String], owner: String, repository: String?) -> [String] {
        guard let repository else { return names }
        return names.map { "\($0)-\(owner)_\(repository)" }
    }

    public var scopeExplanationText: String {
        switch selectedScope {
        case .repository:
            return "Single Repository: Registers runner instance(s) dedicated to one specific GitHub repository."
        case .personalMultiRepo:
            return "Personal Multi-Repo: Since GitHub personal accounts don't have org-wide runners, select multiple repositories below and OctoRunner will provision runners for all of them in one step."
        case .organization:
            return "Organization Pool: Registers runner instance(s) once at the GitHub Organization level so all repositories in that organization can share the runner."
        }
    }

    public func toggleRepositorySelection(_ fullName: String) {
        if selectedRepositoryFullNames.contains(fullName) {
            selectedRepositoryFullNames.remove(fullName)
        } else {
            selectedRepositoryFullNames.insert(fullName)
        }
    }

    public func selectAllRepositories() {
        selectedRepositoryFullNames = Set(repositories.map(\.fullName))
    }

    public func deselectAllRepositories() {
        selectedRepositoryFullNames.removeAll()
    }

    public func toggleLabel(_ label: String) {
        if selectedLabels.contains(label) {
            guard label != "self-hosted" else { return }
            selectedLabels.removeAll { $0 == label }
        } else {
            selectedLabels.append(label)
        }
    }

    public func addCustomLabel() {
        let trimmed = customLabelInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        guard !trimmed.isEmpty else { return }
        if !availableDefaultLabels.contains(trimmed) {
            availableDefaultLabels.append(trimmed)
        }
        if !selectedLabels.contains(trimmed) {
            selectedLabels.append(trimmed)
        }
        customLabelInput = ""
    }

    func targetAccount(forKey key: String?) -> TargetAccount? {
        guard let key, !key.isEmpty else { return nil }
        return TargetAccount(key: key, revision: GitHubAccountStore.selectionRevision)
    }

    public func loadGitHubTargets(forAccountKey key: String?) async {
        guard !Task.isCancelled else { return }
        let requestID = UUID()
        targetLoadID = requestID
        let account = targetAccount(forKey: key)
        if let previous = targetAccount, previous != account {
            repositories = []
            organizations = []
            selectedRepositoryFullName = ""
            selectedRepositoryFullNames = []
            selectedOrganizationLogin = ""
            manualTargetInput = ""
            selectedRunnerGroupID = nil
        }
        targetAccount = account
        isLoadingTargets = false
        guard let account else { return }
        isLoadingTargets = true
        defer {
            if targetLoadID == requestID { isLoadingTargets = false }
        }

        do {
            let token = try await provisioningClient.readToken(for: account.key)
            guard isCurrentTargetLoad(requestID, account: account) else { return }
            async let reposTask = provisioningClient.fetchUserRepositories(token: token)
            async let orgsTask = provisioningClient.fetchUserOrganizations(token: token)

            let fetchedRepos = (try? await reposTask) ?? []
            let fetchedOrgs = (try? await orgsTask) ?? []
            guard isCurrentTargetLoad(requestID, account: account) else { return }
            self.repositories = fetchedRepos
            self.organizations = fetchedOrgs

            if selectedRepositoryFullName.isEmpty, let firstRepo = fetchedRepos.first {
                selectedRepositoryFullName = firstRepo.fullName
            }
            if selectedRepositoryFullNames.isEmpty, let firstRepo = fetchedRepos.first {
                selectedRepositoryFullNames.insert(firstRepo.fullName)
            }
            if selectedOrganizationLogin.isEmpty, let firstOrg = fetchedOrgs.first {
                selectedOrganizationLogin = firstOrg.login
            }
        } catch {
            guard isCurrentTargetLoad(requestID, account: account) else { return }
            self.errorMessage = .failure(error)
        }
    }

    private func isCurrentTargetLoad(_ requestID: UUID, account: TargetAccount) -> Bool {
        !Task.isCancelled && targetLoadID == requestID && GitHubAccountStore.selectionRevision == account.revision
    }

    func organizationSelection(forAccountKey key: String?) -> OrganizationSelection? {
        guard selectedScope == .organization, let key, !key.isEmpty, let scope = resolvedTargetSummary?.scopeURL else {
            return nil
        }
        return OrganizationSelection(key: key, revision: GitHubAccountStore.selectionRevision, scope: scope)
    }

    public func loadRunnerGroups(forAccountKey key: String?) async {
        guard !Task.isCancelled else { return }
        let requestID = UUID()
        groupLoadID = requestID
        let selection = organizationSelection(forAccountKey: key)
        if groupSelection != selection { selectedRunnerGroupID = nil }
        groupSelection = nil
        organizationGroups = []
        groupLookup = nil
        guard let selection else { return }
        do {
            let token = try await provisioningClient.readToken(for: selection.key)
            guard !Task.isCancelled, groupLoadID == requestID, organizationSelection(forAccountKey: key) == selection else { return }
            let result = try await runnerSync.groupInventory(for: selection.scope, token: token) {
                await self.isCurrentGroupLoad(requestID, selection: selection)
            }
            guard !Task.isCancelled, groupLoadID == requestID, organizationSelection(forAccountKey: key) == selection else { return }
            groupLookup = result
            if case .available(let groups, _, _) = result {
                groupSelection = selection
                organizationGroups = groups.filter { !$0.inherited && !$0.isDefault }
            }
        } catch {
            guard !Task.isCancelled, groupLoadID == requestID, organizationSelection(forAccountKey: key) == selection else { return }
            groupLookup = .unavailable
        }
    }

    private func isCurrentGroupLoad(_ id: UUID, selection: OrganizationSelection) -> Bool {
        groupLoadID == id && organizationSelection(forAccountKey: selection.key) == selection
    }

    public var resolvedTargetSummaries: [(owner: String, repo: String?, scopeURL: URL)] {
        let manual = manualTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
        switch selectedScope {
        case .repository:
            let candidate = manual.isEmpty ? selectedRepositoryFullName : manual
            guard let parsed = Self.parseRepoTarget(candidate) else { return [] }
            return [parsed]

        case .personalMultiRepo:
            var targets: [(owner: String, repo: String?, scopeURL: URL)] = []
            var seen: Set<String> = []
            let candidates = selectedRepositoryFullNames.sorted() + manualRepositoryEntries
            for fullName in candidates {
                if let parsed = Self.parseRepoTarget(fullName), seen.insert(parsed.scopeURL.absoluteString.lowercased()).inserted {
                    targets.append(parsed)
                }
            }
            return targets

        case .organization:
            let org = manual.isEmpty ? selectedOrganizationLogin : manual
            guard let url = URL(string: "https://github.com/\(org)"),
                  let target = try? GitHubRunnerProvisioningClient.parseOwnerAndRepo(from: url), target.repo == nil else {
                return []
            }
            return [(owner: target.owner, repo: nil, scopeURL: url)]
        }
    }

    public var resolvedTargetSummary: (owner: String, repo: String?, scopeURL: URL)? {
        resolvedTargetSummaries.first
    }

    private var manualRepositoryEntries: [String] {
        manualTargetInput.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseRepoTarget(_ fullName: String) -> (owner: String, repo: String?, scopeURL: URL)? {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://github.com/\(trimmed)"),
              let target = try? GitHubRunnerProvisioningClient.parseOwnerAndRepo(from: url), let repository = target.repo,
              let canonicalURL = URL(string: "https://github.com/\(target.owner)/\(repository)") else {
            return nil
        }
        return (owner: target.owner, repo: repository, scopeURL: canonicalURL)
    }

    public func provisionAndPersistRunners(
        accountLogin: String?,
        keychainAccountKey: String?,
        modelContext: ModelContext,
        configuration: RunnerLaunchConfiguration = RunnerLaunchConfiguration()
    ) async -> Bool {
        guard !isProvisioning, !provisioningCompleted, !Task.isCancelled else { return false }
        errorMessage = nil
        guard let login = accountLogin, let key = keychainAccountKey, !key.isEmpty else {
            errorMessage = .key("Please sign in with GitHub before provisioning a runner.")
            return false
        }
        if selectedScope == .personalMultiRepo,
           let invalidTarget = manualRepositoryEntries.first(where: { Self.parseRepoTarget($0) == nil }) {
            errorMessage = .key("Enter repositories as owner/repo. Invalid entry: \(invalidTarget).")
            return false
        }
        let targets = resolvedTargetSummaries
        guard !targets.isEmpty else {
            errorMessage = .key("Please select at least one GitHub Repository or Organization.")
            return false
        }
        // Freeze form input before credential loading suspends this actor.
        let names = previewInstanceNames
        let scope: RunnerScopeType = selectedScope == .organization ? .organization : .repository
        let group: GitHubRunnerGroupDTO?
        if scope == .organization, let selectedRunnerGroupID {
            guard groupSelection == organizationSelection(forAccountKey: key),
                  let matched = organizationGroups.first(where: { $0.id == selectedRunnerGroupID }) else {
                errorMessage = .key("The GitHub runner group is no longer available. Check the organization and select a group again.")
                return false
            }
            group = matched
        } else {
            group = nil
        }
        let accountRevision = GitHubAccountStore.selectionRevision
        let labels = selectedLabels
        let launchAgent = registerLaunchAgent

        isProvisioning = true
        defer {
            isProvisioning = false
            provisioningProgressMessage = nil
        }

        do {
            let token = try await provisioningClient.readToken(for: key)
            try Task.checkCancellation()
            var directRunners: [ManagedRunnerConfiguration] = []
            var failedTargets: [String] = []
            var startFailures: [String] = []
            var serviceInstallFailures: [String] = []
            var savedCount = 0
            let verifyAccountSelection: @MainActor @Sendable () throws -> Void = {
                try Task.checkCancellation()
                guard GitHubAccountStore.selectionRevision == accountRevision else { throw CancellationError() }
            }

            for target in targets {
                try Task.checkCancellation()
                guard GitHubAccountStore.selectionRevision == accountRevision else { break }
                let namesForTarget = targets.count > 1
                    ? Self.instanceNames(names, owner: target.owner, repository: target.repo) : names

                let provisionedList: [ProvisionedRunnerSummary]
                do {
                    provisionedList = try await provisionerActor.provisionRunners(
                        instanceNames: namesForTarget, scopeType: scope, scopeURL: target.scopeURL, labels: labels,
                        registerLaunchAgent: launchAgent, accessToken: token, configuration: configuration, runnerGroup: group,
                        verifyAccountSelection: verifyAccountSelection
                    ) { [weak self] message in
                        guard !Task.isCancelled else { return }
                        self?.provisioningProgressMessage = message
                    }
                } catch is CancellationError {
                    try Task.checkCancellation()
                    break
                } catch RunnerMigrationError.groupChanged {
                    errorMessage = .key("The GitHub runner group is no longer available. Check the organization and select a group again.")
                    return false
                } catch {
                    guard targets.count > 1 else { throw error }
                    failedTargets.append(target.scopeURL.path().trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                    continue
                }

                try Task.checkCancellation()
                if provisionedList.count < namesForTarget.count {
                    failedTargets.append(target.scopeURL.path().trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                }
                try modelContext.transaction {
                    for summary in provisionedList {
                        let id = UUID()
                        let mode: RunnerExecutionMode = summary.launchdLabel == nil ? .direct : .launchAgent
                        let entity = RunnerEntity(
                            id: id,
                            name: summary.name,
                            scopeType: summary.scopeType,
                            scopeUrl: summary.scopeURL,
                            status: .offline,
                            labels: summary.labels,
                            workDirectory: summary.workDirectory,
                            rootDirectoryPath: summary.rootDirectory.path(percentEncoded: false),
                            runnerVersion: summary.runnerVersion,
                            pid: summary.pid,
                            executionMode: mode
                        )
                        entity.githubRunnerId = summary.remoteID
                        entity.githubRunnerGroupID = summary.remoteGroupID
                        entity.githubRunnerGroupName = summary.remoteGroupName
                        if let label = summary.launchdLabel {
                            entity.serviceLabel = label
                        }
                        modelContext.insert(entity)
                        modelContext.insert(AuditLogEntity(
                            category: .runnerLifecycle,
                            title: "Runner Provisioned",
                            summary: "Provisioned \(summary.name) (\(summary.scopeURL.absoluteString), v\(summary.runnerVersion))",
                            actorAccountLogin: login,
                            targetRunnerName: summary.name,
                            newValue: summary.labels.joined(separator: ",")
                        ))
                        if launchAgent && (summary.launchAgentFailed || summary.launchdLabel == nil) {
                            if mode == .direct {
                                serviceInstallFailures.append(summary.name)
                            } else {
                                startFailures.append(summary.name)
                            }
                            modelContext.insert(AuditLogEntity(
                                category: .runnerLifecycle, severity: .warning, title: "Runner Start Failed",
                                summary: "Could not start \(summary.name) (\(id.uuidString)).",
                                actorAccountLogin: login, targetRunnerName: summary.name
                            ))
                        } else if mode == .direct {
                            directRunners.append(.init(runnerID: id, name: summary.name, rootDirectory: summary.rootDirectory,
                                mode: .direct, launch: configuration))
                        }
                    }
                }
                savedCount += provisionedList.count
            }
            provisioningCompleted = savedCount > 0
            guard GitHubAccountStore.selectionRevision == accountRevision else {
                errorMessage = .key("GitHub account changed during setup. Saved registrations: \(savedCount).")
                return provisioningCompleted
            }
            for runner in directRunners {
                try Task.checkCancellation()
                do {
                    try await supervisor.configure(runner)
                    try await supervisor.start(runnerID: runner.runnerID)
                } catch is CancellationError {
                    return false
                } catch {
                    try Task.checkCancellation()
                    startFailures.append(runner.name)
                    AuditLogRecorder.record(
                        in: modelContext,
                        category: .runnerLifecycle,
                        severity: .warning,
                        title: "Runner Start Failed",
                        summary: "Could not start \(runner.name) (\(runner.runnerID.uuidString)).",
                        actorAccountLogin: login,
                        targetRunnerName: runner.name
                    )
                }
            }
            if !failedTargets.isEmpty {
                errorMessage = .key("Runner setup incomplete for \(failedTargets.joined(separator: ", ")). Saved registrations: \(savedCount).")
            } else if !serviceInstallFailures.isEmpty {
                errorMessage = .key("The background service could not be installed for \(serviceInstallFailures.joined(separator: ", ")). Start these runners manually from Runner Settings.")
            } else if !startFailures.isEmpty {
                errorMessage = .key("Registered but could not start: \(startFailures.joined(separator: ", ")). Open Runner Settings to retry.")
            }
            return provisioningCompleted
        } catch is CancellationError {
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            errorMessage = .failure(error)
            return false
        }
    }
}
