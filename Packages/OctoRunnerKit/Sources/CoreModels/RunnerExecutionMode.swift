public enum RunnerExecutionMode: String, Codable, CaseIterable, Sendable {
    case direct
    case launchAgent
    case external
}
