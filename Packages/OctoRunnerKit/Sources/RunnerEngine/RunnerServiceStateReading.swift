public protocol RunnerServiceStateReading: Sendable {
    func isUnloaded(label: String) async throws -> Bool
}
