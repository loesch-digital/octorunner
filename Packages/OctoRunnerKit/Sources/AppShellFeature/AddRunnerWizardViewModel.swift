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
    public var selectedOrganizationLogin: String = ""
    public var manualTargetInput: String = ""

    public var instanceCount: Int = 2
    public var baseNamePrefix: String = {
        let host = ProcessInfo.processInfo.hostName
            .replacingOccurrences(of: ".local", with: "")
            .lowercased()
        return host.isEmpty ? "mac-runner" : "\(host)-runner"
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

    private let provisioningClient: GitHubRunnerProvisioningClient
    private let provisionerActor: RunnerProvisionerActor
    private let vault: KeychainVaultActor

    public init(
        provisioningClient: GitHubRunnerProvisioningClient = GitHubRunnerProvisioningClient(),
        provisionerActor: RunnerProvisionerActor = RunnerProvisionerActor(),
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

    public func loadGitHubTargets(forAccountLogin login: String?) async {
        guard let login else { return }
        isLoadingTargets = true
        defer { isLoadingTargets = false }

        do {
            let token = try await provisioningClient.readToken(for: login)
            async let reposTask = provisioningClient.fetchUserRepositories(token: token)
            async let orgsTask = provisioningClient.fetchUserOrganizations(token: token)

            let fetchedRepos = (try? await reposTask) ?? []
            let fetchedOrgs = (try? await orgsTask) ?? []
            self.repositories = fetchedRepos
            self.organizations = fetchedOrgs

            if selectedRepositoryFullName.isEmpty, let firstRepo = fetchedRepos.first {
                selectedRepositoryFullName = firstRepo.fullName
            }
            if selectedOrganizationLogin.isEmpty, let firstOrg = fetchedOrgs.first {
                selectedOrganizationLogin = firstOrg.login
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public var resolvedTargetSummary: (owner: String, repo: String?, scopeURL: URL)? {
        switch selectedScope {
        case .repository, .personalMultiRepo:
            let candidate = !selectedRepositoryFullName.isEmpty
                ? selectedRepositoryFullName
                : manualTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = candidate.split(separator: "/").map(String.init)
            guard parts.count == 2,
                  let url = URL(string: "https://github.com/\(parts[0])/\(parts[1])") else {
                return nil
            }
            return (owner: parts[0], repo: parts[1], scopeURL: url)
        case .organization:
            let org = !selectedOrganizationLogin.isEmpty
                ? selectedOrganizationLogin
                : manualTargetInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !org.isEmpty,
                  let url = URL(string: "https://github.com/\(org)") else {
                return nil
            }
            return (owner: org, repo: nil, scopeURL: url)
        }
    }

    public func provisionAndPersistRunners(
        accountLogin: String?,
        modelContext: ModelContext
    ) async -> Bool {
        errorMessage = nil
        guard let login = accountLogin else {
            errorMessage = "Please sign in with GitHub before provisioning a runner."
            return false
        }
        guard let target = resolvedTargetSummary else {
            errorMessage = "Please select or enter a valid GitHub Repository (owner/repo) or Organization."
            return false
        }

        isProvisioning = true
        defer {
            isProvisioning = false
            provisioningProgressMessage = nil
        }

        do {
            let token = try await provisioningClient.readToken(for: login)

            let provisionedList = try await provisionerActor.provisionRunners(
                instanceNames: previewInstanceNames,
                scopeType: selectedScope,
                scopeURL: target.scopeURL,
                labels: selectedLabels,
                registerLaunchAgent: registerLaunchAgent,
                accessToken: token
            ) { [weak self] message in
                await MainActor.run {
                    self?.provisioningProgressMessage = message
                }
            }

            for summary in provisionedList {
                let entity = RunnerEntity(
                    name: summary.name,
                    scopeType: summary.scopeType,
                    scopeUrl: summary.scopeURL,
                    status: .idle,
                    labels: summary.labels,
                    workDirectory: summary.workDirectory,
                    rootDirectoryPath: summary.rootDirectory.path(),
                    runnerVersion: summary.runnerVersion,
                    isImportedLocal: false,
                    pid: summary.pid
                )
                if let label = summary.launchdLabel {
                    entity.serviceLabel = label
                }
                modelContext.insert(entity)
            }
            try? modelContext.save()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
