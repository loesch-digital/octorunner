import CoreModels
import Foundation
import GitHubAPI
import Observation
import RunnerEngine
import SecurityKit
import SwiftData

@MainActor
@Observable
public final class AddRunnerWizardViewModel {
    public var selectedScope: RunnerScopeType = .repository
    public var repositories: [GitHubRepositorySummaryDTO] = []
    public var organizations: [GitHubOrganizationSummaryDTO] = []
    public var selectedRepositoryFullName: String = ""
    public var selectedRepositoryFullNames: Set<String> = []
    public var selectedOrganizationLogin: String = ""
    public var manualTargetInput: String = ""

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
    public var provisioningProgressMessage: String?
    public var errorMessage: String?

    private let provisioningClient: any RunnerTargetLoading
    private let provisionerActor: any RunnerProvisioning
    private let vault: KeychainVaultActor

    public init(
        provisioningClient: any RunnerTargetLoading = GitHubRunnerProvisioningClient(),
        provisionerActor: any RunnerProvisioning = RunnerProvisionerActor(),
        vault: KeychainVaultActor = KeychainVaultActor()
    ) {
        self.provisioningClient = provisioningClient
        self.provisionerActor = provisionerActor
        self.vault = vault
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

    public func loadGitHubTargets(forAccountKey key: String?) async {
        guard let key, !key.isEmpty else { return }
        isLoadingTargets = true
        defer { isLoadingTargets = false }

        do {
            let token = try await provisioningClient.readToken(for: key)
            async let reposTask = provisioningClient.fetchUserRepositories(token: token)
            async let orgsTask = provisioningClient.fetchUserOrganizations(token: token)

            let fetchedRepos = (try? await reposTask) ?? []
            let fetchedOrgs = (try? await orgsTask) ?? []
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
            self.errorMessage = error.localizedDescription
        }
    }

    public var resolvedTargetSummaries: [(owner: String, repo: String?, scopeURL: URL)] {
        switch selectedScope {
        case .repository:
            let candidate = !selectedRepositoryFullName.isEmpty
                ? selectedRepositoryFullName
                : manualTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = Self.parseRepoTarget(candidate) else { return [] }
            return [parsed]

        case .personalMultiRepo:
            var targets: [(owner: String, repo: String?, scopeURL: URL)] = []
            for fullName in selectedRepositoryFullNames.sorted() {
                if let parsed = Self.parseRepoTarget(fullName) {
                    targets.append(parsed)
                }
            }
            if targets.isEmpty {
                let manual = manualTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = Self.parseRepoTarget(manual) {
                    targets.append(parsed)
                }
            }
            return targets

        case .organization:
            let org = !selectedOrganizationLogin.isEmpty
                ? selectedOrganizationLogin
                : manualTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !org.isEmpty,
                  let url = URL(string: "https://github.com/\(org)") else {
                return []
            }
            return [(owner: org, repo: nil, scopeURL: url)]
        }
    }

    public var resolvedTargetSummary: (owner: String, repo: String?, scopeURL: URL)? {
        resolvedTargetSummaries.first
    }

    private static func parseRepoTarget(_ fullName: String) -> (owner: String, repo: String?, scopeURL: URL)? {
        let parts = fullName.split(separator: "/").map(String.init)
        guard parts.count == 2,
              let url = URL(string: "https://github.com/\(parts[0])/\(parts[1])") else {
            return nil
        }
        return (owner: parts[0], repo: parts[1], scopeURL: url)
    }

    public func provisionAndPersistRunners(
        accountLogin: String?,
        keychainAccountKey: String?,
        modelContext: ModelContext,
        configuration: RunnerLaunchConfiguration = RunnerLaunchConfiguration()
    ) async -> Bool {
        guard !isProvisioning, !Task.isCancelled else { return false }
        errorMessage = nil
        guard let login = accountLogin, let key = keychainAccountKey, !key.isEmpty else {
            errorMessage = "Please sign in with GitHub before provisioning a runner."
            return false
        }
        let targets = resolvedTargetSummaries
        guard !targets.isEmpty else {
            errorMessage = "Please select at least one GitHub Repository or Organization."
            return false
        }
        // Freeze form input before credential loading suspends this actor.
        let names = previewInstanceNames
        let scope = selectedScope
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

            for target in targets {
                try Task.checkCancellation()
                let suffix = targets.count > 1 && target.repo != nil ? "-\(target.repo!)" : ""
                let namesForTarget = names.map { "\($0)\(suffix)" }

                let provisionedList = try await provisionerActor.provisionRunners(
                    instanceNames: namesForTarget,
                    scopeType: scope,
                    scopeURL: target.scopeURL,
                    labels: labels,
                    registerLaunchAgent: launchAgent,
                    accessToken: token,
                    configuration: configuration
                ) { [weak self] message in
                    guard !Task.isCancelled else { return }
                    self?.provisioningProgressMessage = message
                }

                try Task.checkCancellation()
                for summary in provisionedList {
                    let entity = RunnerEntity(
                        name: summary.name,
                        scopeType: summary.scopeType,
                        scopeUrl: summary.scopeURL,
                        status: .idle,
                        labels: summary.labels,
                        workDirectory: summary.workDirectory,
                        rootDirectoryPath: summary.rootDirectory.path(percentEncoded: false),
                        runnerVersion: summary.runnerVersion,
                        isImportedLocal: false,
                        pid: summary.pid
                    )
                    if let label = summary.launchdLabel {
                        entity.serviceLabel = label
                    }
                    modelContext.insert(entity)

                    AuditLogRecorder.record(
                        in: modelContext,
                        category: .runnerLifecycle,
                        severity: .info,
                        title: "Runner Provisioned",
                        summary: "Provisioned \(summary.name) (\(summary.scopeURL.absoluteString), v\(summary.runnerVersion))",
                        actorAccountLogin: login,
                        targetRunnerName: summary.name,
                        newValue: summary.labels.joined(separator: ",")
                    )
                }
            }
            try modelContext.save()
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }
}
