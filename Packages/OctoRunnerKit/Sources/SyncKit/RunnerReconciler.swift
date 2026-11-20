import CoreModels
import Foundation

public enum RunnerRemotePresence: Sendable, Equatable {
    case reported(RunnerStatus)
    case differentRegistration
    case notFound
    case unauthorized
    case forbidden
    case rateLimited(retryAt: Date)
    case unavailable
}

public struct RunnerReconciliation: Sendable, Equatable {
    public let presence: RunnerRemotePresence
    public let hasStatusConflict: Bool
    public let hasLabelConflict: Bool
}

public enum RunnerReconciler {
    public static func compare(
        expectedID: Int64,
        expectedName: String,
        localStatus: RunnerStatus,
        localLabels: [String],
        result: RunnerLookupResult
    ) -> RunnerReconciliation {
        switch result {
        case .found(let remote, _):
            guard remote.id == expectedID, remote.name == expectedName else {
                return observation(.differentRegistration)
            }
            let remoteStatus: RunnerStatus
            switch (remote.status, remote.busy) {
            case ("online", true): remoteStatus = .busy
            case ("online", false): remoteStatus = .idle
            case ("offline", false): remoteStatus = .offline
            default: return observation(.unavailable)
            }
            let localPresence = localStatus == .faulted ? .offline : localStatus
            return .init(
                presence: .reported(remoteStatus),
                hasStatusConflict: localPresence != .restarting && localPresence != remoteStatus,
                hasLabelConflict: Set(localLabels.map { $0.lowercased() }) != Set(remote.labelNames.map { $0.lowercased() })
            )
        case .notFound: return observation(.notFound)
        case .unauthorized: return observation(.unauthorized)
        case .forbidden: return observation(.forbidden)
        case .rateLimited(let retryAt): return observation(.rateLimited(retryAt: retryAt))
        case .notModified, .unavailable: return observation(.unavailable)
        }
    }

    private static func observation(_ presence: RunnerRemotePresence) -> RunnerReconciliation {
        .init(presence: presence, hasStatusConflict: false, hasLabelConflict: false)
    }
}
