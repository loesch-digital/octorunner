import CoreModels
import DesignSystem
import SwiftUI

public struct WorkflowHistoryContent: View {
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    let entries: [WorkflowHistoryEntry]
    let repositories: [String]
    @Binding var repository: String
    @Binding var filter: WorkflowHistoryFilter
    @Binding var durationTarget: Int?
    let isLoading: Bool
    let errorMessage: String?
    let lastRefresh: Date?
    let rateLimitRemaining: Int?
    let canLoadOlder: Bool
    let refresh: () -> Void
    let loadOlder: () -> Void

    public init(entries: [WorkflowHistoryEntry], repositories: [String], repository: Binding<String>, filter: Binding<WorkflowHistoryFilter>, durationTarget: Binding<Int?>, isLoading: Bool, errorMessage: String?, lastRefresh: Date?, rateLimitRemaining: Int?, canLoadOlder: Bool, refresh: @escaping () -> Void, loadOlder: @escaping () -> Void) {
        self.entries = entries; self.repositories = repositories
        _repository = repository; _filter = filter; _durationTarget = durationTarget
        self.isLoading = isLoading; self.errorMessage = errorMessage; self.lastRefresh = lastRefresh
        self.rateLimitRemaining = rateLimitRemaining; self.canLoadOlder = canLoadOlder
        self.refresh = refresh; self.loadOlder = loadOlder
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        var effectiveFilter = filter
        effectiveFilter.repository = repository.isEmpty ? nil : repository
        let rows = effectiveFilter.apply(to: entries)
        let included = Set(rows.map(\.id))
        // Metrics use the same filtered workflows; job rows never multiply run counts.
        let metrics = WorkflowHistoryMetrics(entries: entries.filter { included.contains($0.id) }, now: now, calendar: calendar, durationSLASeconds: durationTarget.map(Double.init))
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Jobs & Workflow Runs", bundle: .module).font(.title2.bold())
                        Text("Metrics describe the loaded history window", bundle: .module).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(action: refresh) {
                        Label { Text("Refresh", bundle: .module) } icon: { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(isLoading)
                    .accessibilityLabel(Text("Refresh workflow history", bundle: .module))
                    .accessibilityHint(Text("Loads recent runs from the selected repositories", bundle: .module))
                }
                if isLoading { ProgressView().controlSize(.small).accessibilityLabel(Text("Loading history", bundle: .module)) }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(OctoTheme.warningOrange).font(.callout)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    metric("Running / queued", value: "\(metrics.runningCount) / \(metrics.queuedCount)")
                    metric("Completed today", value: metrics.completedToday.formatted(.number.locale(locale)))
                    metric("Success rate", value: percent(metrics.successRate))
                    metric("Average duration", value: metrics.averageDurationSeconds.map { Duration.seconds($0).formatted(.time(pattern: .minuteSecond)) } ?? "—")
                    metric("Within duration target", value: percent(metrics.durationSLARate))
                    if metrics.stalePendingCount > 0 { metric("Stale pending runs", value: "\(metrics.stalePendingCount)") }
                }
                filters
                if let lastRefresh {
                    HStack {
                        Text("Last response", bundle: .module)
                        Text(lastRefresh, format: .dateTime.hour().minute().second())
                        Spacer()
                        if let rateLimitRemaining { Text("API: \(rateLimitRemaining)") }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                if rows.isEmpty {
                    ContentUnavailableView {
                        Label { Text("No matching workflow runs", bundle: .module) } icon: { Image(systemName: "list.bullet.rectangle") }
                    } description: { Text("Add a repository, refresh or adjust the filters", bundle: .module) }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(rows) { entry in
                            WorkflowRunHistoryRow(entry: entry, jobs: entries.filter {
                                $0.recordKind == "job" && $0.accountID == entry.accountID && $0.repository == entry.repository && $0.githubRunID == entry.githubRunID && $0.attempt == entry.attempt
                            }.sorted { ($0.githubJobID ?? 0) < ($1.githubJobID ?? 0) }, now: now)
                        }
                    }
                }
                Button(action: loadOlder) { Text("Load older runs", bundle: .module) }
                    .disabled(isLoading || !canLoadOlder)
                    .accessibilityLabel(Text("Load older runs", bundle: .module))
                    .accessibilityHint(Text("Select one repository to load its next history page", bundle: .module))
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.background(OctoTheme.surfaceLowest)
    }

    private var filters: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
            Picker(selection: $filter.status) {
                ForEach(WorkflowHistoryStatusFilter.allCases, id: \.self) { status in
                    Text(statusTitle(status)).tag(status)
                }
            } label: { Text("Status", bundle: .module) }
            .accessibilityLabel(Text("Workflow status", bundle: .module))
            .accessibilityHint(Text("Filters the latest attempt of each workflow run", bundle: .module))
            Picker(selection: $repository) {
                Text("All repositories", bundle: .module).tag("")
                ForEach(repositories, id: \.self) { Text($0).lineLimit(1).truncationMode(.middle).tag($0) }
            } label: { Text("Repository", bundle: .module) }
            .help(repository.isEmpty ? AppLocalization.string("All repositories", locale: locale) : repository)
            .accessibilityLabel(Text("Repository", bundle: .module))
            .accessibilityHint(Text("Chooses which repository to display and refresh", bundle: .module))
            Picker(selection: $filter.runnerID) {
                Text("All runners", bundle: .module).tag(Int64?.none)
                ForEach(runnerIDs, id: \.self) { id in
                    Text(entries.first { $0.runnerID == id }?.runnerName ?? "#\(id)").tag(Optional(id))
                }
            } label: { Text("Runner", bundle: .module) }
            .accessibilityLabel(Text("Assigned runner", bundle: .module))
            .accessibilityHint(Text("Filters runs containing a job assigned to this runner", bundle: .module))
            TextField(text: $filter.search) { Text("Workflow, branch or commit", bundle: .module) }
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text("Search workflow history", bundle: .module))
                .accessibilityHint(Text("Filters loaded workflow names, repositories, branches and commits", bundle: .module))
            Picker(selection: $durationTarget) {
                Text("Not configured", bundle: .module).tag(Int?.none)
                ForEach(Array(Set([60, 300, 600, 1800, 3600] + (durationTarget.map { [$0] } ?? []))).sorted(), id: \.self) { seconds in
                    Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))).tag(Optional(seconds))
                }
            } label: { Text("Duration target", bundle: .module) }
            .accessibilityLabel(Text("Workflow duration target", bundle: .module))
            .accessibilityHint(Text("Optional target for the measured workflow duration metric", bundle: .module))
        }
    }

    private var runnerIDs: [Int64] { Array(Set(entries.compactMap(\.runnerID))).sorted() }
    private func percent(_ value: Double?) -> String { value?.formatted(.percent.precision(.fractionLength(1)).locale(locale)) ?? "—" }
    private func metric(_ title: String.LocalizationValue, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLocalization.string(title, locale: locale)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).lineLimit(1)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
    }
    private func statusTitle(_ status: WorkflowHistoryStatusFilter) -> String {
        let title: String.LocalizationValue = switch status {
        case .all: "All statuses"
        case .running: "Running"
        case .queued: "Queued"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
        return AppLocalization.string(title, locale: locale)
    }
}
