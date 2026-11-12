import CoreModels
import Foundation

public struct RunnerHealthTransitionTracker: Sendable {
    private var previous: [UUID: RunnerStatus] = [:]

    public init() {}

    public mutating func consume(_ observations: [RunnerHealthObservation], at now: Date, locale: Locale = .current) -> [AppNotificationEvent] {
        var current: [UUID: RunnerStatus] = [:]
        var events: [AppNotificationEvent] = []
        for observation in observations where observation.isFresh(at: now) {
            guard let status = observation.status else { continue }
            current[observation.id] = status
            guard let old = previous[observation.id], old != status else { continue }
            let wasOnline = old == .idle || old == .busy
            let isOnline = status == .idle || status == .busy
            let kind: AppNotificationKind
            let title: String
            if status == .faulted {
                kind = .runnerError
                title = AppLocalization.string("Runner error", locale: locale)
            } else if status == .offline && wasOnline {
                kind = .runnerOffline
                title = AppLocalization.string("Runner process stopped", locale: locale)
            } else if isOnline && !wasOnline {
                kind = .runnerOnline
                title = AppLocalization.string("Runner process started", locale: locale)
            } else { continue }
            events.append(AppNotificationEvent(id: "runner-transition-\(observation.id)-\(UUID())", kind: kind, title: title, message: observation.name))
        }
        previous = current
        return events
    }
}
