import CoreModels
import Foundation

public struct RunnerRecoveryEvent: Sendable {
    public enum Kind: Sendable { case crash, quarantine }

    public let runnerID: UUID
    public let runnerName: String
    public let generation: UUID
    public let kind: Kind
    public let exitStatus: Int32?
    public let shouldNotify: Bool
}

enum RunnerRestartDecision: Equatable {
    case stop
    case retry(after: Duration)
    case quarantine
}

struct RunnerRestartHistory {
    private static let stableUptime: Duration = .seconds(60)
    private var consecutiveFailures = 0
    private var notifiedCrash = false

    mutating func markFirstCrash() -> Bool {
        guard !notifiedCrash else { return false }
        notifiedCrash = true
        return true
    }

    mutating func record(settings: RunnerRuntimePolicy, status: Int32?, uptime: Duration, intentional: Bool) -> RunnerRestartDecision {
        let stable = uptime >= Self.stableUptime
        if stable || intentional {
            consecutiveFailures = 0
            notifiedCrash = false
        }

        guard !intentional, settings.restartPolicy != .manual,
              settings.restartPolicy == .always || status != 0 else {
            consecutiveFailures = 0
            return .stop
        }

        // An immediate successful exit also counts under Always so a listener
        // that returns without staying alive cannot restart forever.
        if !stable || status != 0 { consecutiveFailures += 1 }
        if consecutiveFailures >= settings.quarantineThreshold { return .quarantine }
        return .retry(after: .seconds(settings.restartDelaySeconds))
    }
}
