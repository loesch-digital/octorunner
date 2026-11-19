import Foundation
@testable import RunnerEngine
import Testing

struct RunnerAdmissionTests {
    @Test("Capacity goes to the oldest pending runner after the active generation exits")
    func fifoAdmission() {
        let first = ticket()
        let second = ticket()
        let third = ticket()
        var admission = RunnerAdmissionController(limit: 1)
        #expect(admission.request(first) == .admitted)
        #expect(admission.request(second) == .waiting)
        #expect(admission.request(third) == .waiting)
        #expect(admission.request(second) == .waiting)
        admission.release(first)
        #expect(admission.request(third) == .waiting)
        #expect(admission.request(second) == .admitted)
        #expect(admission.request(third) == .waiting)
    }

    @Test("Lowering the limit retains active slots and blocks new starts until capacity returns")
    func lowerLimit() {
        let first = ticket()
        let second = ticket()
        let waiting = ticket()
        var admission = RunnerAdmissionController(limit: 2)
        #expect(admission.request(first) == .admitted)
        #expect(admission.request(second) == .admitted)
        admission.setLimit(1)
        #expect(admission.activeCount == 2)
        #expect(admission.request(waiting) == .waiting)
        admission.release(first)
        #expect(admission.request(waiting) == .waiting)
        admission.release(second)
        #expect(admission.request(waiting) == .admitted)
    }

    @Test("Cancellation and release only affect the matching generation")
    func generationIsolation() {
        let first = ticket()
        let next = RunnerAdmissionTicket(runnerID: first.runnerID, generation: UUID())
        var admission = RunnerAdmissionController(limit: 1)
        #expect(admission.request(first) == .admitted)
        #expect(admission.request(next) == .waiting)
        admission.cancel(first)
        #expect(admission.nextWaiting == next)
        admission.release(first)
        #expect(admission.request(next) == .admitted)
        admission.release(first)
        #expect(admission.activeCount == 1)
        admission.release(next)
        #expect(admission.activeCount == 0)
    }

    private func ticket() -> RunnerAdmissionTicket {
        RunnerAdmissionTicket(runnerID: UUID(), generation: UUID())
    }
}
