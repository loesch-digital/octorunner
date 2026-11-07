import Foundation

public enum RunnerLogLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERR"
    case success = "OK"

    public var id: String { rawValue }
}
