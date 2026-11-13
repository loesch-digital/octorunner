public protocol RunnerProcessSampling: Sendable {
    func sample() async throws -> [String: RunnerProcessPresence]
}
