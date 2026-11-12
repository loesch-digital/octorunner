import AppKit
import AppShellFeature
import CoreModels
import Foundation
import GitHubAPI
import SwiftData
import SwiftUI
import Synchronization
import Testing

@MainActor
struct ResponsiveLayoutTests {
    private static var retainedContainers: [ModelContainer] = []

    @Test("Wizard reports the total across targets rather than instances per repository")
    func plannedRunnerCountIncludesEveryTarget() {
        let vm = AddRunnerWizardViewModel()
        #expect(vm.plannedRunnerCount == 0)
        vm.selectedScope = .personalMultiRepo
        vm.selectedRepositoryFullNames = Set((1...80).map { "owner/repo-\($0)" })
        vm.instanceCount = 8
        #expect(vm.plannedRunnerCount == 640)
        vm.selectedRepositoryFullNames.insert("invalid")
        #expect(vm.plannedRunnerCount == 640)
        vm.selectedScope = .repository
        vm.manualTargetInput = "owner/single"
        #expect(vm.plannedRunnerCount == 8)
        vm.selectedScope = .organization
        vm.selectedOrganizationLogin = "organization"
        vm.instanceCount = 1
        #expect(vm.plannedRunnerCount == 1)
    }

    @Test("New Runner honors finite viewport sizes with many repositories, labels and long names")
    func populatedWizardFitsViewport() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        let vm = AddRunnerWizardViewModel()
        vm.selectedScope = .personalMultiRepo
        vm.instanceCount = 8
        vm.baseNamePrefix = "mac-studio-with-a-long-descriptive-runner-name-for-builds"
        vm.repositories = try JSONDecoder().decode([GitHubRepositorySummaryDTO].self, from: JSONSerialization.data(withJSONObject: (1...80).map {
            ["id": $0, "name": "repository-\($0)", "full_name": "organization-with-a-long-name/repository-with-a-long-descriptive-name-\($0)",
             "html_url": "https://github.com/example/repository-\($0)", "private": true] as [String: Any]
        }))
        vm.selectedRepositoryFullNames = Set(vm.repositories.map(\.fullName))
        vm.availableDefaultLabels += (1...20).map { "long-custom-build-capability-label-\($0)" }
        let defaultsName = "octorunner-layout-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let preferences = AppPreferencesStore(defaults: defaults)
        for appearance in [ColorScheme.light, .dark] {
            for feedbackVisible in [false, true] {
                vm.errorMessage = feedbackVisible ? String(repeating: "Provisioning failed for a repository with a long name. ", count: 20) : nil
                vm.provisioningProgressMessage = feedbackVisible ? "Preparing runner 640 of 640 for organization-with-a-long-name/repository-with-a-long-name" : nil
                for viewport in [CGSize(width: 560, height: 480), CGSize(width: 640, height: 640), CGSize(width: 900, height: 800)] {
                    let measurement = LayoutMeasurement()
                    let host = NSHostingView(rootView: FixedTestViewport(size: viewport, measurement: measurement) {
                        AddRunnerWizardSheet(viewModel: vm)
                    }.environment(preferences).modelContainer(container).preferredColorScheme(appearance))
                    host.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
                    host.frame = CGRect(origin: .zero, size: viewport)
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    let measured = try #require(measurement.size.withLock { $0 })
                    // This is the child's response to a finite proposed viewport, not
                    // NSHostingView's unconstrained intrinsic/ideal fittingSize.
                    #expect(measured.width <= viewport.width, "Proposed: \(viewport), child: \(measured)")
                    #expect(measured.height <= viewport.height, "Proposed: \(viewport), child: \(measured)")
                    #expect(measured.width > 0 && measured.height > 0)
                    if let path = ProcessInfo.processInfo.environment["OCTORUNNER_LAYOUT_CAPTURE_DIR"] {
                        let url = URL(fileURLWithPath: path).appending(path: "wizard-\(Int(viewport.width))x\(Int(viewport.height))-\(appearance == .dark ? "dark" : "light")-\(feedbackVisible ? "feedback" : "normal").png")
                        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
                    }
                }
            }
        }
    }
}

private final class LayoutMeasurement: Sendable {
    let size = Mutex<CGSize?>(nil)
}

private struct FixedTestViewport: Layout {
    let size: CGSize
    let measurement: LayoutMeasurement
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let childProposal = ProposedViewSize(size)
        measurement.size.withLock { $0 = child.sizeThatFits(childProposal) }
        child.place(at: bounds.origin, anchor: .topLeading, proposal: childProposal)
    }
}
