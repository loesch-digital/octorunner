import Foundation

public enum RunnerRestartPolicy: String, CaseIterable, Codable, Sendable, Identifiable {
    case always
    case onNonZeroExit
    case manual

    public var id: String { rawValue }
}
