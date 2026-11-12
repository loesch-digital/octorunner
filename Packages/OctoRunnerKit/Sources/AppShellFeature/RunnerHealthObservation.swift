import CoreModels
import Foundation

public struct RunnerHealthObservation: Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let status: RunnerStatus?
    public let observedAt: Date

    public init(id: UUID, name: String, status: RunnerStatus?, observedAt: Date) {
        self.id = id
        self.name = name
        self.status = status
        self.observedAt = observedAt
    }

    public func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(observedAt)
        return age >= -5 && age <= 60 && status != nil
    }
}
