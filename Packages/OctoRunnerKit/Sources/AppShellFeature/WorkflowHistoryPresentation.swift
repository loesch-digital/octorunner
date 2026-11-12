import CoreModels
import Foundation

struct WorkflowHistoryPresentation {
    let status: String
    let symbol: String
    let githubURL: URL?

    init(entry: WorkflowHistoryEntry, now: Date = .now, locale: Locale = .current) {
        let key: String.LocalizationValue
        if entry.status != "completed", !entry.isFresh(at: now) {
            key = "Stale"; symbol = "clock.badge.questionmark"
        } else {
            switch (entry.status, entry.conclusion) {
            case ("completed", "success"): key = "Succeeded"; symbol = "checkmark.circle.fill"
            case ("completed", "cancelled"): key = "Cancelled"; symbol = "slash.circle"
            case ("completed", "failure"), ("completed", "timed_out"), ("completed", "startup_failure"), ("completed", "action_required"), ("completed", "stale"):
                key = "Failed"; symbol = "xmark.circle.fill"
            case ("completed", _): key = "Completed"; symbol = "checkmark.circle"
            case ("in_progress", _): key = "Running"; symbol = "play.circle.fill"
            case ("queued", _), ("waiting", _), ("pending", _), ("requested", _): key = "Queued"; symbol = "clock"
            default: key = "Unknown"; symbol = "questionmark.circle"
            }
        }
        status = AppLocalization.string(key, locale: locale)
        githubURL = Self.validatedURL(entry)
    }

    private static func validatedURL(_ entry: WorkflowHistoryEntry) -> URL? {
        guard let url = entry.htmlURL, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host?.lowercased() == "github.com",
              components.port == nil || components.port == 443, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let slug = GitHubRepositorySlug(input: entry.repository) else { return nil }
        let path = components.percentEncodedPath.lowercased()
        let base = "/\(slug.rawValue)/actions/runs/\(entry.githubRunID)"
        if path == base { return url }
        if let attempt = entry.attempt, path == "\(base)/attempts/\(attempt)" { return url }
        return nil
    }
}
