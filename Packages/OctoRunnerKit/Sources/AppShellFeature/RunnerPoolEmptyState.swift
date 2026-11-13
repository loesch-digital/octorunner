import CoreModels

/// A filtered-out pool is different from an installation without any registered runners.
enum RunnerPoolEmptyState: Equatable {
    case unregistered, noFaulted, noActive, noSearchMatches

    init(registeredCount: Int, section: SidebarSection, search: String) {
        if registeredCount == 0 { self = .unregistered }
        else if !search.isEmpty { self = .noSearchMatches }
        else if section == .failedFaulted { self = .noFaulted }
        else if section == .activeDaemons { self = .noActive }
        else { self = .noSearchMatches }
    }
}
