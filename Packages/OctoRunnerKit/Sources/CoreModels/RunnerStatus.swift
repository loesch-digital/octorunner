import Foundation

public enum RunnerStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case idle = "idle"
    case busy = "busy"
    case offline = "offline"
    case faulted = "faulted"
    case restarting = "restarting"

    public var id: String { rawValue }

    public var badgeTitle: String {
        switch self {
        case .idle:
            return "IDLE"
        case .busy:
            return "RUNNING"
        case .offline:
            return "OFFLINE"
        case .faulted:
            return "FAULTED"
        case .restarting:
            return "RESTARTING"
        }
    }
}
