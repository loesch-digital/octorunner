import CoreModels
import DesignSystem
import SwiftUI

struct RunnerTargetSelection: View {
    @Environment(\.locale) private var locale
    let viewModel: AddRunnerWizardViewModel

    var body: some View {
        @Bindable var vm = viewModel
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
                multiRepositoryControls
            case .organization:
                organizationControls
            }
        }
        .padding(12)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
    }

    @ViewBuilder
    private var multiRepositoryControls: some View {
        @Bindable var vm = viewModel
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
    }

    @ViewBuilder
    private var organizationControls: some View {
        @Bindable var vm = viewModel
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
}
