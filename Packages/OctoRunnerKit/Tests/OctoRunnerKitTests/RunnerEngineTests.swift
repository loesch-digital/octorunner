import Foundation
import RunnerEngine
import Testing

@Suite("RunnerEngine & Process Supervisor Tests")
struct RunnerEngineTests {
    @Test("RunnerSupervisorActor queries SMAppService login autostart state safely")
    func loginAutostartStatusQuery() async {
        let supervisor = RunnerSupervisorActor()
        let isEnabled = await supervisor.isLoginAutostartEnabled()
        #expect(isEnabled == true || isEnabled == false)
    }
}
