import Foundation

public struct WorkflowHistoryPreferences: Codable, Equatable, Sendable {
    public var additionalRepositoriesByAccount: [String: [String]] = [:]
    public var durationSLATargetSeconds: Int? = nil
    public var refreshIntervalSeconds: Int = 60

    public init() {}

    public func validated() -> Self {
        var result = self
        result.additionalRepositoriesByAccount = additionalRepositoriesByAccount.reduce(into: [:]) { accounts, item in
            guard let id = Int64(item.key), id > 0, String(id) == item.key else { return }
            accounts[item.key] = Array(Set(item.value.compactMap { input in
                // Persist plain identities only; URL input must first pass the explicit input parser.
                guard !input.contains("://") else { return nil as String? }
                return GitHubRepositorySlug(input: input)?.rawValue
            })).sorted()
        }
        if let target = durationSLATargetSeconds, !(1...86_400).contains(target) {
            result.durationSLATargetSeconds = nil
        }
        result.refreshIntervalSeconds = min(max(refreshIntervalSeconds, 60), 900)
        return result
    }
}
