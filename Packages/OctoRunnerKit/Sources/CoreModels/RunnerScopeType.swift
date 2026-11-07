import Foundation

public enum RunnerScopeType: String, CaseIterable, Codable, Sendable, Identifiable {
    case personalMultiRepo = "personal"
    case organization = "organization"
    case repository = "repository"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .personalMultiRepo:
            return "Personal Account"
        case .organization:
            return "Organization"
        case .repository:
            return "Repository"
        }
    }
}
