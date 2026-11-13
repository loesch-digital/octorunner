import CoreModels
import SwiftData
import DesignSystem
import SwiftUI
import TelemetryKit

public struct HostTelemetryDashboardView: View {
    let accountID: Int64?
    let rateBudget: WorkflowHistoryRateBudget
    @Query(sort: \RunnerEntity.name) private var runners: [RunnerEntity]
    @State private var inspector = RunnerProcessInspectorModel()
    @State private var interval = 5
    @State private var refreshID = 0
    @State private var host: HostTelemetrySnapshot?
    @State private var disk: HostDiskIOSnapshot?
    @State private var capacity: VolumeCapacitySnapshot?
    private let hostSampler = HostTelemetryActor()
    private let diskSampler = HostDiskIOMonitor()
    private let capacitySampler = SystemVolumeCapacitySampler()

    public init(accountID: Int64?, rateBudget: WorkflowHistoryRateBudget) {
        self.accountID = accountID
        self.rateBudget = rateBudget
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) { heading; Spacer(); controls }
                    VStack(alignment: .leading, spacing: 12) { heading; controls }
                }
                HostTelemetryCards(host: host, disk: disk, capacity: capacity, rate: accountID.flatMap { rateBudget.snapshot(for: $0) })
                RunnerProcessInspectorView(model: inspector, targets: processTargets)
            }.padding(20)
        }
        .background(OctoTheme.surfaceLowest)
        .task(id: TelemetrySamplingRequest(interval: interval, refreshID: refreshID, targets: processTargets)) {
            guard !Task.isCancelled else { return }
            let targets = processTargets
            while !Task.isCancelled {
                let nextHost = await hostSampler.currentSnapshot()
                guard !Task.isCancelled else { return }
                let nextDisk = await diskSampler.currentSnapshot()
                guard !Task.isCancelled else { return }
                let nextCapacity = await capacitySampler.sample()
                guard !Task.isCancelled else { return }
                host = nextHost; disk = nextDisk; capacity = nextCapacity
                await inspector.refresh(targets: targets)
                guard !Task.isCancelled else { return }
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            }
        }
    }

    private var processTargets: [RunnerProcessTarget] {
        runners.compactMap { runner in
            guard let root = runner.rootDirectoryPath, !root.isEmpty else { return nil }
            return RunnerProcessTarget(id: runner.id, name: runner.name, rootPath: root)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Host Telemetry", bundle: .module).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text(host?.osVersionString ?? "—").foregroundStyle(OctoTheme.secondaryText)
        }
    }

    private var controls: some View {
        HStack {
            Picker(selection: $interval) {
                Text("1 s").tag(1)
                Text("5 s").tag(5)
                Text("15 s").tag(15)
            } label: { Text("Sample interval", bundle: .module) }
            .fixedSize()
            .accessibilityLabel(Text("Sample interval", bundle: .module))
            .accessibilityHint(Text("Change how often host metrics are sampled while this screen is open.", bundle: .module))
            Button { refreshID += 1 } label: {
                Label { Text("Refresh telemetry", bundle: .module) } icon: { Image(systemName: "arrow.clockwise") }
            }
            .accessibilityLabel(Text("Refresh telemetry", bundle: .module))
            .accessibilityHint(Text("Take a new local measurement now.", bundle: .module))
        }
    }
}
