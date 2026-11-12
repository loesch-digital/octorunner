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

    @Test("Workflow history fits small windows with long names and many loaded jobs")
    func workflowHistoryFits() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        let run = JobRunEntity(githubRunId: 42, workflowName: String(repeating: "Long workflow name ", count: 8), repositoryFullName: "organization-with-a-long-name/repository-with-a-long-name", branchName: String(repeating: "branch-", count: 20), commitSha: String(repeating: "a", count: 40), statusRaw: "in_progress")
        run.accountGitHubUserID = 7
        run.runAttempt = 1
        run.observedAt = .now
        container.mainContext.insert(run)
        run.sourceRaw = "github"
        var entries = [WorkflowHistoryEntry(run)]
        for number in 1...80 {
            let job = JobRunEntity(githubRunId: 42, workflowName: run.workflowName, repositoryFullName: run.repositoryFullName, branchName: run.branchName, commitSha: run.commitSha, statusRaw: "in_progress")
            job.recordKindRaw = "job"
            job.accountGitHubUserID = 7
            job.runAttempt = 1
            job.githubJobId = Int64(number)
            job.jobName = String(repeating: "matrix-build-name-", count: 8)
            job.runnerNameSnapshot = String(repeating: "runner-name-", count: 8)
            job.observedAt = .now
            job.sourceRaw = "github"
            container.mainContext.insert(job)
            entries.append(WorkflowHistoryEntry(job))
        }
        for scheme in [ColorScheme.light, .dark] {
            for viewport in [CGSize(width: 560, height: 480), CGSize(width: 900, height: 800)] {
                let measurement = LayoutMeasurement()
                let host = NSHostingView(rootView: FixedTestViewport(size: viewport, measurement: measurement) {
                    WorkflowHistoryContent(entries: entries, repositories: [run.repositoryFullName] + (1...80).map { "long-organization/repository-\($0)" }, repository: .constant(run.repositoryFullName), filter: .constant(WorkflowHistoryFilter()), durationTarget: .constant(nil), isLoading: false, errorMessage: nil, lastRefresh: .now, rateLimitRemaining: 4990, canLoadOlder: false, refresh: {}, loadOlder: {})
                }.preferredColorScheme(scheme).environment(\.locale, Locale(identifier: "de")))
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                host.frame = CGRect(origin: .zero, size: viewport)
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let measured = try #require(measurement.size.withLock { $0 })
                #expect(measured.width <= viewport.width && measured.height <= viewport.height)
                if let path = ProcessInfo.processInfo.environment["OCTORUNNER_LAYOUT_CAPTURE_DIR"] {
                    try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path).appending(path: "history-\(Int(viewport.width))-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
    }

    @Test("Dashboard runner rows stay within narrow and wide viewports with long metadata")
    func dashboardRunnerRowsFit() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        let runner = RunnerEntity(name: String(repeating: "long-runner-name-", count: 6),
            scopeUrl: try #require(URL(string: "https://github.com/organization-with-a-long-name/repository-with-a-long-name")),
            status: .busy, labels: (1...30).map { "long-capability-label-\($0)" },
            workDirectory: URL(fileURLWithPath: "/tmp/layout-fixture"), runnerVersion: "2.999.123", isImportedLocal: true, pid: 12345)
        container.mainContext.insert(runner)
        for width in [320.0, 560, 900] {
            let viewport = CGSize(width: width, height: 200)
            let measurement = LayoutMeasurement()
            let host = NSHostingView(rootView: FixedTestViewport(size: viewport, measurement: measurement) {
                DashboardRunnerRow(runner: runner, openLog: {}, openSettings: {}, migrate: {}, remove: {})
            }.modelContainer(container))
            host.frame = CGRect(origin: .zero, size: viewport)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let measured = try #require(measurement.size.withLock { $0 })
            #expect(measured.width <= width)
            #expect(measured.height <= 200)
            if let path = ProcessInfo.processInfo.environment["OCTORUNNER_LAYOUT_CAPTURE_DIR"] {
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path).appending(path: "dashboard-row-\(Int(width)).png"))
            }
        }
    }

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
