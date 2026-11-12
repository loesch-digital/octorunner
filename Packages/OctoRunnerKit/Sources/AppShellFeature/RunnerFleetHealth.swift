import CoreModels
import Foundation

public enum RunnerFleetHealth: Sendable, Equatable, CaseIterable {
    case unknown, healthy, busy, offline, faulted

    public static func summarize(_ observations: [RunnerHealthObservation], at now: Date) -> Self {
        let fresh = observations.filter { $0.isFresh(at: now) }
        if fresh.contains(where: { $0.status == .faulted }) { return .faulted }
        if fresh.contains(where: { $0.status == .offline }) { return .offline }
        guard !observations.isEmpty, fresh.count == observations.count else { return .unknown }
        if fresh.contains(where: { $0.status == .busy || $0.status == .restarting }) { return .busy }
        return .healthy
    }
}
