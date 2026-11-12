import Foundation

public struct GitHubRateLimitSnapshot: Sendable, Equatable {
    public let limit: Int?
    public let remaining: Int?
    public let resetAt: Date?
    public let retryAfterSeconds: TimeInterval?
    public let observedAt: Date

    init(headers: [String: String], observedAt: Date = .now) {
        func nonnegative(_ value: String?) -> Int? {
            guard let value, let number = Int(value), number >= 0 else { return nil }
            return number
        }
        limit = nonnegative(headers["x-ratelimit-limit"])
        remaining = nonnegative(headers["x-ratelimit-remaining"])
        resetAt = nonnegative(headers["x-ratelimit-reset"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        retryAfterSeconds = nonnegative(headers["retry-after"]).map(TimeInterval.init)
        self.observedAt = observedAt
    }
}
