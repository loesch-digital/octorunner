import CoreModels
import DesignSystem
import RunnerEngine
import SwiftData
import SwiftUI

public struct AddRunnerWizardSheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppPreferencesStore.self) private var preferences
    @Query(sort: \GitHubAccountEntity.connectedAt, order: .reverse) private var accounts: [GitHubAccountEntity]

    @State private var viewModel: AddRunnerWizardViewModel
    @State private var provisioningTask: Task<Void, Never>?

    public init(viewModel: AddRunnerWizardViewModel = AddRunnerWizardViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        @Bindable var bindableVM = viewModel
        let accountKey = accounts.first(where: { $0.isActive })?.keychainAccountKey

        VStack(alignment: .leading, spacing: 14) {
            headerSection

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    scopePickerSection(bindableVM: bindableVM)
                    targetSelectionSection(bindableVM: bindableVM)
                    instanceCountAndNamingSection(bindableVM: bindableVM)
                    labelsSection(bindableVM: bindableVM)
                    RunnerWorkspaceHelp()
                    launchAgentSection(bindableVM: bindableVM)
                    RunnerProvisioningFeedback(progress: viewModel.provisioningProgressMessage, errorMessage: viewModel.errorMessage)
                }
                .padding(.vertical, 2)
            }

            Divider()

            footerActions
        }
        .padding(22)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 420, idealHeight: 680)
        .background(OctoTheme.surfaceLowest)
        .task(id: viewModel.targetAccount(forKey: accountKey)) {
            await viewModel.loadGitHubTargets(forAccountKey: accountKey)
        }
        .task(id: viewModel.organizationSelection(forAccountKey: accountKey)) {
            await viewModel.loadRunnerGroups(forAccountKey: accountKey)
        }
        .interactiveDismissDisabled(viewModel.isProvisioning)
        .onDisappear { provisioningTask?.cancel() }
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.rectangle.on.folder.fill")
                .font(.system(size: 22))
                .foregroundStyle(OctoTheme.accentBlue)
                .frame(width: 40, height: 40)
                .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.string("Add Self-Hosted Runner Setup Wizard", locale: locale))
                    .font(.system(size: 17, weight: .bold))
                Text(AppLocalization.string("Configure target scope, parallel runner instances, labels & automatic background start.", locale: locale))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func infoCallout(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(OctoTheme.accentBlue)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 6))
    }

    private func scopePickerSection(bindableVM: AddRunnerWizardViewModel) -> some View {
        @Bindable var vm = bindableVM
        return VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.string("1. Runner Registration Scope", locale: locale))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker(AppLocalization.string("Scope", locale: locale), selection: $vm.selectedScope) {
                Text(AppLocalization.string("Single Repository", locale: locale)).tag(RunnerScopeType.repository)
                Text(AppLocalization.string("Personal Account (Multi-Repo)", locale: locale)).tag(RunnerScopeType.personalMultiRepo)
                Text(AppLocalization.string("Organization Pool", locale: locale)).tag(RunnerScopeType.organization)
            }
            .pickerStyle(.menu)
            .accessibilityLabel(AppLocalization.string("Runner registration scope", locale: locale))
            .accessibilityHint(AppLocalization.string("Select one repository, multiple personal repositories, or an organization pool", locale: locale))

            infoCallout(AppLocalization.string(String.LocalizationValue(stringLiteral: vm.scopeExplanationText), locale: locale))
        }
        .padding(12)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
    }

    private func targetSelectionSection(bindableVM: AddRunnerWizardViewModel) -> some View {
        @Bindable var vm = bindableVM
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(targetSectionTitle(for: vm.selectedScope))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if vm.isLoadingTargets {
                    ProgressView().controlSize(.small)
                } else if vm.selectedScope == .personalMultiRepo && !vm.repositories.isEmpty {
                    HStack(spacing: 8) {
                        Button(AppLocalization.string("Select All", locale: locale), action: vm.selectAllRepositories)
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                        Button(AppLocalization.string("Clear", locale: locale), action: vm.deselectAllRepositories)
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                    }
                }
            }

            switch vm.selectedScope {
            case .repository:
                if !vm.repositories.isEmpty {
                    Picker(AppLocalization.string("Repository", locale: locale), selection: $vm.selectedRepositoryFullName) {
                        ForEach(vm.repositories) { repo in
                            Text(repo.fullName + (repo.isPrivate ? AppLocalization.string("Private repository suffix", locale: locale) : ""))
                                .tag(repo.fullName)
                        }
                    }
                    .labelsHidden()
                }
                TextField(AppLocalization.string("Or enter owner/repo manually (e.g. loesch-digital/itemflux-ios-app)", locale: locale), text: $vm.manualTargetInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

            case .personalMultiRepo:
                if !vm.repositories.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(vm.repositories) { repo in
                                let isChecked = vm.selectedRepositoryFullNames.contains(repo.fullName)
                                Button {
                                    vm.toggleRepositorySelection(repo.fullName)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(isChecked ? OctoTheme.accentBlue : .secondary)
                                        Text(repo.fullName)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .help(repo.fullName)
                                        if repo.isPrivate {
                                            Text(AppLocalization.string("PRIVATE", locale: locale))
                                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 3))
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Repository \(repo.fullName)")
                                .accessibilityValue(isChecked ? AppLocalization.string("Selected", locale: locale) : AppLocalization.string("Not selected", locale: locale))
                                .accessibilityHint(AppLocalization.string("Toggles this repository in the runner setup", locale: locale))
                            }
                        }
                    }
                    .frame(maxHeight: 115)
                    .background(OctoTheme.surfaceLowest, in: .rect(cornerRadius: 6))
                }
                TextField(AppLocalization.string("Repositories as owner/repo, separated by commas", locale: locale), text: $vm.manualTargetInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .accessibilityHint(Text("Creates a separate runner registration for each repository.", bundle: .module))

            case .organization:
                if !vm.organizations.isEmpty {
                    Picker(AppLocalization.string("Organization", locale: locale), selection: $vm.selectedOrganizationLogin) {
                        ForEach(vm.organizations) { org in
                            Text(org.login).tag(org.login)
                        }
                    }
                    .labelsHidden()
                }
                TextField(AppLocalization.string("Or enter organization slug (e.g. loesch-digital)", locale: locale), text: $vm.manualTargetInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Picker(selection: $vm.selectedRunnerGroupID) {
                    Text("Default group", bundle: .module).tag(nil as Int64?)
                    ForEach(vm.organizationGroups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                } label: {
                    Text("GitHub runner group", bundle: .module)
                }
                .accessibilityHint(Text("Selects the organization group that controls repository access.", bundle: .module))
                if let lookup = vm.groupLookup {
                    switch lookup {
                    case .available:
                        EmptyView()
                    case .forbidden:
                        Text("The selected account cannot list this organization's runner groups.", bundle: .module)
                            .foregroundStyle(OctoTheme.warningOrange)
                    case .unauthorized:
                        Text("Reconnect GitHub to load runner groups.", bundle: .module)
                            .foregroundStyle(OctoTheme.warningOrange)
                    case .rateLimited, .unavailable:
                        Text("GitHub runner groups are currently unavailable.", bundle: .module)
                            .foregroundStyle(OctoTheme.secondaryText)
                    }
                }
            }
        }
        .padding(12)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
    }

    private func targetSectionTitle(for scope: RunnerScopeType) -> String {
        switch scope {
        case .repository:
            return AppLocalization.string("2. Target GitHub Repository (Single Selection)", locale: locale)
        case .personalMultiRepo:
            return AppLocalization.string("2. Select Repositories (\(viewModel.selectedRepositoryFullNames.count) selected)", locale: locale)
        case .organization:
            return AppLocalization.string("2. Target GitHub Organization", locale: locale)
        }
    }

    private func instanceCountAndNamingSection(bindableVM: AddRunnerWizardViewModel) -> some View {
        @Bindable var vm = bindableVM
        return VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.string("3. Base Runner Prefix & Parallel Instance Count", locale: locale))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            infoCallout(
                AppLocalization.string("GitHub requires a unique name for each runner. The Base Prefix (e.g. 'mac-runner') is combined with the instance number ('mac-runner-1', 'mac-runner-2'). Each instance gets its own isolated '_work' folder so multiple CI jobs can run in parallel.", locale: locale)
            )

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string("Base Runner Prefix", locale: locale))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("mac-runner", text: $vm.baseNamePrefix)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }

                Divider()
                    .frame(height: 36)

                Stepper(value: $vm.instanceCount, in: 1...8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppLocalization.string("Instances: \(vm.instanceCount)", locale: locale))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                        Text(AppLocalization.string("Parallel _work folders", locale: locale))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(vm.plannedNameExamples, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(OctoTheme.accentBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 5))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
    }

    private func labelsSection(bindableVM: AddRunnerWizardViewModel) -> some View {
        @Bindable var vm = bindableVM
        return VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.string("4. Runner Labels (Workflow 'runs-on' Matching)", locale: locale))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            infoCallout(
                AppLocalization.string("GitHub Actions workflows use 'runs-on: [self-hosted, macos, arm64]' to route jobs to matching runners. Click any label below to toggle it or add custom capability tags (like 'fastlane').", locale: locale)
            )

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(vm.availableDefaultLabels, id: \.self) { label in
                        let isSelected = vm.selectedLabels.contains(label)
                        Button {
                            vm.toggleLabel(label)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 11))
                                Text(label)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .foregroundStyle(isSelected ? .white : .primary)
                            .background(
                                isSelected ? OctoTheme.accentBlue : OctoTheme.surfaceHigh,
                                in: .rect(cornerRadius: 6)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 8) {
                TextField(AppLocalization.string("Add custom label (e.g. fastlane, testflight)…", locale: locale), text: $vm.customLabelInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit {
                        vm.addCustomLabel()
                    }
                Button(AppLocalization.string("Add Label", locale: locale), systemImage: "plus", action: vm.addCustomLabel)
                    .buttonStyle(.bordered)
                    .disabled(vm.customLabelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
    }

    private func launchAgentSection(bindableVM: AddRunnerWizardViewModel) -> some View {
        @Bindable var vm = bindableVM
        return Toggle(isOn: $vm.registerLaunchAgent) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.string("Automatic Background Start (Run on macOS Login)", locale: locale))
                    .font(.system(size: 12, weight: .semibold))
                Text("Installs a runner LaunchAgent that starts at login. The restart policy and PATH come from Settings.", bundle: .module)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(12)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
    }

    private var footerActions: some View {
        HStack {
            Button(AppLocalization.string(viewModel.provisioningCompleted ? "Done" : "Cancel", locale: locale)) {
                dismiss()
            }
            .disabled(viewModel.isProvisioning)

            Spacer()

            Button {
                let configuration = RunnerLaunchConfiguration(runtimePolicy: preferences.runtimePolicy, inheritHostPath: preferences.inheritHostPath)
                let account = accounts.first(where: { $0.isActive })
                let login = account?.login
                let key = account?.keychainAccountKey
                provisioningTask = Task {
                    let ok = await viewModel.provisionAndPersistRunners(
                        accountLogin: login,
                        keychainAccountKey: key,
                        modelContext: modelContext,
                        configuration: configuration
                    )
                    if ok && !Task.isCancelled && viewModel.errorMessage == nil {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isProvisioning {
                        ProgressView().controlSize(.small)
                        Text(AppLocalization.string("Provisioning…", locale: locale))
                    } else {
                        Image(systemName: "bolt.fill")
                        Text(AppLocalization.string("Create & Start (\(viewModel.plannedRunnerCount))", locale: locale))
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OctoTheme.accentBlue)
            .disabled(viewModel.isProvisioning || viewModel.provisioningCompleted || viewModel.plannedRunnerCount == 0)
            .accessibilityLabel(AppLocalization.string("Create and start \(viewModel.plannedRunnerCount) runners", locale: locale))
            .accessibilityHint(AppLocalization.string("Creates the selected number of instances for every selected target", locale: locale))
        }
    }
}

#Preview("AddRunnerWizardSheet — Step 3 Setup Wizard") {
    AddRunnerWizardSheet()
        .environment(AppPreferencesStore())
        .preferredColorScheme(.dark)
}
