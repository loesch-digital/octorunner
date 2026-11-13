import Foundation

/// Keep names from removed runners available independently of the selected filters and page.
enum AuditRunnerOptions {
    static func names(registered: [String], historical: [String?]) -> [String] {
        Set(registered + historical.compactMap { $0 })
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
