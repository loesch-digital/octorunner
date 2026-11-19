import Foundation

struct RunnerAdmissionTicket: Equatable, Sendable {
    let runnerID: UUID
    let generation: UUID
}

enum RunnerAdmissionDecision: Equatable {
    case admitted
    case waiting
}

/// Stored by the supervisor so checking capacity and claiming a slot share its
/// actor isolation. Lowering the limit affects only future admissions.
struct RunnerAdmissionController {
    private var limit: Int
    private var active: [UUID: UUID] = [:]
    private var waiting: [RunnerAdmissionTicket] = []

    init(limit: Int) {
        self.limit = Self.clamped(limit)
    }

    var activeCount: Int { active.count }
    var nextWaiting: RunnerAdmissionTicket? { waiting.first }
    var hasCapacity: Bool { active.count < limit }

    mutating func setLimit(_ limit: Int) {
        self.limit = Self.clamped(limit)
    }

    mutating func request(_ ticket: RunnerAdmissionTicket) -> RunnerAdmissionDecision {
        if active[ticket.runnerID] == ticket.generation { return .admitted }
        enqueue(ticket)
        guard hasCapacity, waiting.first == ticket, active[ticket.runnerID] == nil else { return .waiting }
        waiting.removeFirst()
        active[ticket.runnerID] = ticket.generation
        return .admitted
    }

    mutating func enqueue(_ ticket: RunnerAdmissionTicket) {
        if !waiting.contains(ticket) { waiting.append(ticket) }
    }

    mutating func cancel(_ ticket: RunnerAdmissionTicket) {
        waiting.removeAll { $0 == ticket }
    }

    mutating func release(_ ticket: RunnerAdmissionTicket) {
        guard active[ticket.runnerID] == ticket.generation else { return }
        active.removeValue(forKey: ticket.runnerID)
    }

    private static func clamped(_ limit: Int) -> Int {
        min(max(limit, 1), 64)
    }
}
