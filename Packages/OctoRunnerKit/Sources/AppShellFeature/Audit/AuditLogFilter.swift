import CoreModels
import Foundation
import SwiftData

struct AuditLogFilter: Equatable {
    var category: AuditEventCategory?
    var severity: AuditEventSeverity?
    var runnerName: String?
    var search = ""

    func descriptor(limit: Int) -> FetchDescriptor<AuditLogEntity> {
        let category = category?.rawValue ?? ""
        let severity = severity?.rawValue ?? ""
        let runner = runnerName ?? ""
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate = #Predicate<AuditLogEntity> { event in
            (category == "" || event.categoryRaw == category) &&
            (severity == "" || event.severityRaw == severity) &&
            (runner == "" || event.targetRunnerName == runner) &&
            (query == "" || event.title.localizedStandardContains(query) ||
                event.summary.localizedStandardContains(query))
        }
        var descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\AuditLogEntity.timestamp, order: .reverse)])
        descriptor.fetchLimit = max(1, limit)
        return descriptor
    }
}
