import CoreModels
import DesignSystem
import SwiftData
import SwiftUI

public struct AddRunnerWizardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GitHubAccountEntity.connectedAt, order: .reverse) private var accounts: [GitHubAccountEntity]

    @State private var viewModel: AddRunnerWizardViewModel

    public init(viewModel: AddRunnerWizardViewModel = AddRunnerWizardViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        @Bindable var bindableVM = viewModel

        VStack(alignment: .leading, spacing: 18) {
            headerSection

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
        .padding(24)
        .frame(width: 640, height: 620)
        .background(OctoTheme.surfaceLowest)
        .task {
            await viewModel.loadGitHubTargets(forAccountLogin: accounts.first?.login)
        }
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.rectangle.on.folder.fill")
                .font(.system(size: 24))
                .foregroundStyle(OctoTheme.accentBlue)
                .frame(width: 42, height: 42)
                .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text("Add Self-Hosted Runner Setup Wizard")
                    .font(.system(size: 17, weight: .bold))
                Text("Configure scope, parallel runner instances, labels & macOS LaunchAgent supervision.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func scopePickerSection(bindableVM: AddRunnerWizardViewModel) -> some View {
        @Bindable var vm = bindableVM
        return VStack(alignment: .leading, spacing: 8) {
            Text("1. Runner Registration Scope")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Scope", selection: $vm.selectedScope) {
                Text("Repository").tag(RunnerScopeType.repository)
                Text("Organization").tag(RunnerScopeType.organization)
                Text("Personal Account Repos").tag(RunnerScopeType.personalMultiRepo)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func targetSelectionSection(bindableVM: AddRunnerWizardViewModel) -> some View {
        @Bindable var vm = bindableVM
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(vm.selectedScope == .organization ? "2. Target GitHub Organization" : "2. Target GitHub Repository")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if vm.isLoadingTargets {
                    ProgressView().controlSize(.small)
                }
            }

            if vm.selectedScope == .organization {
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
            } else {
                if !vm.repositories.isEmpty {
                    Picker("Repository", selection: $vm.selectedRepositoryFullName) {
                        ForEach(vm.repositories) { repo in
                            Text("\(repo.fullName)\(repo.isPrivate ? " (Private)" : "")")
                                .tag(repo.fullName)
                        }
                    }
                    .labelsHidden()
                }
                TextField("Or enter owner/repo (e.g. loesch-digital/itemflux-ios-app)", text: $vm.manualTargetInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }
        }
        .padding(12)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
    }

    private func instanceCountAndNamingSection(bindableVM: AddRunnerWizardViewModel) -> some View {
        @Bindable var vm = bindableVM
        return VStack(alignment: .leading, spacing: 10) {
            Text("3. Instance Count & Base Name")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

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
                        Text("Parallel _work directories")
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
        return VStack(alignment: .leading, spacing: 10) {
            Text("4. Runner Labels (runs-on)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

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
                Text("Register macOS User LaunchAgent (~/Library/LaunchAgents)")
                    .font(.system(size: 12, weight: .semibold))
                Text("Automatically restarts runner instances on login and crash with /opt/homebrew/bin in PATH.")
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
                Task {
                    let ok = await viewModel.provisionAndPersistRunners(
                        accountLogin: accounts.first?.login,
                        modelContext: modelContext
                    )
                    if ok {
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
        .preferredColorScheme(.dark)
}
