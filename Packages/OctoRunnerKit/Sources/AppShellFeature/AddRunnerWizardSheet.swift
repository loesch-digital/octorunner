import CoreModels
import DesignSystem
import RunnerEngine
import SwiftData
import SwiftUI

public struct AddRunnerWizardSheet: View {
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

        VStack(alignment: .leading, spacing: 14) {
            headerSection

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    scopePickerSection(bindableVM: bindableVM)
                    targetSelectionSection(bindableVM: bindableVM)
                    instanceCountAndNamingSection(bindableVM: bindableVM)
                    labelsSection(bindableVM: bindableVM)
                    launchAgentSection(bindableVM: bindableVM)
                }
                .padding(.vertical, 2)
            }

            if let progress = viewModel.provisioningProgressMessage {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progress)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(OctoTheme.accentBlue)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 8))
            }

            if let errorMessage = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(OctoTheme.errorRed)
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(OctoTheme.errorRed)
                }
            }

            Divider()

            footerActions
        }
        .padding(22)
        .frame(width: 640, height: 640)
        .background(OctoTheme.surfaceLowest)
        .task {
            await viewModel.loadGitHubTargets(forAccountLogin: accounts.first?.login)
        }
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
                Text("Add Self-Hosted Runner Setup Wizard")
                    .font(.system(size: 17, weight: .bold))
                Text("Configure target scope, parallel runner instances, labels & automatic background start.")
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
            Text("1. Runner Registration Scope")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Scope", selection: $vm.selectedScope) {
                Text("Single Repository").tag(RunnerScopeType.repository)
                Text("Personal Account (Multi-Repo)").tag(RunnerScopeType.personalMultiRepo)
                Text("Organization Pool").tag(RunnerScopeType.organization)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            infoCallout(vm.scopeExplanationText)
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
                        Button("Select All", action: vm.selectAllRepositories)
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                        Button("Clear", action: vm.deselectAllRepositories)
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                    }
                }
            }

            switch vm.selectedScope {
            case .repository:
                if !vm.repositories.isEmpty {
                    Picker("Repository", selection: $vm.selectedRepositoryFullName) {
                        ForEach(vm.repositories) { repo in
                            Text("\(repo.fullName)\(repo.isPrivate ? " (Private)" : "")")
                                .tag(repo.fullName)
                        }
                    }
                    .labelsHidden()
                }
                TextField("Or enter owner/repo manually (e.g. loesch-digital/itemflux-ios-app)", text: $vm.manualTargetInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

            case .personalMultiRepo:
                if !vm.repositories.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
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
                                        if repo.isPrivate {
                                            Text("PRIVATE")
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
                            }
                        }
                    }
                    .frame(maxHeight: 115)
                    .background(OctoTheme.surfaceLowest, in: .rect(cornerRadius: 6))
                } else {
                    TextField("Enter owner/repo (e.g. loesch-digital/itemflux-ios-app)", text: $vm.manualTargetInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }

            case .organization:
                if !vm.organizations.isEmpty {
                    Picker("Organization", selection: $vm.selectedOrganizationLogin) {
                        ForEach(vm.organizations) { org in
                            Text(org.login).tag(org.login)
                        }
                    }
                    .labelsHidden()
                }
                TextField("Or enter organization slug (e.g. loesch-digital)", text: $vm.manualTargetInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
        }
        .padding(12)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
    }

    private func targetSectionTitle(for scope: RunnerScopeType) -> String {
        switch scope {
        case .repository:
            return "2. Target GitHub Repository (Single Selection)"
        case .personalMultiRepo:
            return "2. Select Repositories (\(viewModel.selectedRepositoryFullNames.count) selected)"
        case .organization:
            return "2. Target GitHub Organization"
        }
    }

    private func instanceCountAndNamingSection(bindableVM: AddRunnerWizardViewModel) -> some View {
        @Bindable var vm = bindableVM
        return VStack(alignment: .leading, spacing: 8) {
            Text("3. Base Runner Prefix & Parallel Instance Count")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            infoCallout(
                "GitHub requires a unique name for each runner. The Base Prefix (e.g. 'mac-runner') is combined with the instance number ('mac-runner-1', 'mac-runner-2'). Each instance gets its own isolated '_work' folder so multiple CI jobs can run in parallel."
            )

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Base Runner Prefix")
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
                        Text("\(vm.instanceCount) Instance\(vm.instanceCount > 1 ? "s" : "")")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                        Text("Parallel _work folders")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(vm.previewInstanceNames, id: \.self) { name in
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
            Text("4. Runner Labels (Workflow 'runs-on' Matching)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            infoCallout(
                "GitHub Actions workflows use 'runs-on: [self-hosted, macos, arm64]' to route jobs to matching runners. Click any label below to toggle it or add custom capability tags (like 'fastlane')."
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
                TextField("Add custom label (e.g. fastlane, testflight)…", text: $vm.customLabelInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit {
                        vm.addCustomLabel()
                    }
                Button("Add Label", systemImage: "plus", action: vm.addCustomLabel)
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
                Text("Automatic Background Start (Run on macOS Login)")
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
            Button("Cancel") {
                dismiss()
            }
            .disabled(viewModel.isProvisioning)

            Spacer()

            Button {
                let configuration = RunnerLaunchConfiguration(runtimePolicy: preferences.runtimePolicy, inheritHostPath: preferences.inheritHostPath)
                let login = accounts.first?.login
                provisioningTask = Task {
                    let ok = await viewModel.provisionAndPersistRunners(
                        accountLogin: login,
                        modelContext: modelContext,
                        configuration: configuration
                    )
                    if ok && !Task.isCancelled {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isProvisioning {
                        ProgressView().controlSize(.small)
                        Text("Provisioning…")
                    } else {
                        Image(systemName: "bolt.fill")
                        Text("Create & Start \(viewModel.instanceCount) Runner\(viewModel.instanceCount > 1 ? "s" : "")")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OctoTheme.accentBlue)
            .disabled(viewModel.isProvisioning)
        }
    }
}

#Preview("AddRunnerWizardSheet — Step 3 Setup Wizard") {
    AddRunnerWizardSheet()
        .environment(AppPreferencesStore())
        .preferredColorScheme(.dark)
}
