import CoreModels
@testable import RunnerEngine
import Testing

struct RunnerRestartPolicyTests {
    @Test("A quick clean exit counts toward quarantine without consuming the first crash notification")
    func firstCrashAfterCleanExit() {
        var history = RunnerRestartHistory()
        let settings = RunnerRuntimePolicy()
        _ = history.record(settings: settings, status: 0, uptime: .seconds(1), intentional: false)
        _ = history.record(settings: settings, status: 1, uptime: .seconds(1), intentional: false)
        let firstCrash = history.markFirstCrash()
        #expect(firstCrash)
        _ = history.record(settings: settings, status: 1, uptime: .seconds(1), intentional: false)
        let repeatedCrash = history.markFirstCrash()
        #expect(!repeatedCrash)
        _ = history.record(settings: settings, status: 1, uptime: .seconds(60), intentional: false)
        let crashAfterStableRun = history.markFirstCrash()
        #expect(crashAfterStableRun)
    }

    @Test("Restart policy distinguishes success, errors, and voluntary stops",
          arguments: [RunnerRestartPolicy.always, .onNonZeroExit, .manual])
    func exitPolicy(policy: RunnerRestartPolicy) {
        var settings = RunnerRuntimePolicy()
        settings.restartPolicy = policy
        var history = RunnerRestartHistory()
        #expect(history.record(settings: settings, status: 0, uptime: .seconds(5), intentional: false)
            == (policy == .always ? .retry(after: .seconds(10)) : .stop))
        #expect(history.record(settings: settings, status: -9, uptime: .seconds(5), intentional: false)
            == (policy == .manual ? .stop : .retry(after: .seconds(10))))
        #expect(history.record(settings: settings, status: -15, uptime: .seconds(5), intentional: true) == .stop)
    }

    @Test("The Nth failed attempt quarantines and a stable run resets the failure count")
    func quarantineThreshold() {
        var settings = RunnerRuntimePolicy()
        settings.quarantineThreshold = 3
        settings.restartDelaySeconds = 4
        var history = RunnerRestartHistory()
        #expect(history.record(settings: settings, status: 1, uptime: .seconds(1), intentional: false) == .retry(after: .seconds(4)))
        #expect(history.record(settings: settings, status: nil, uptime: .zero, intentional: false) == .retry(after: .seconds(4)))
        #expect(history.record(settings: settings, status: 1, uptime: .seconds(60), intentional: false) == .retry(after: .seconds(4)))
        #expect(history.record(settings: settings, status: 1, uptime: .seconds(1), intentional: false) == .retry(after: .seconds(4)))
        #expect(history.record(settings: settings, status: nil, uptime: .zero, intentional: false) == .quarantine)
    }

    @Test("The Always policy cannot loop indefinitely if the runner exits immediately with success")
    func repeatedSuccessfulEarlyExits() {
        var settings = RunnerRuntimePolicy()
        settings.quarantineThreshold = 2
        var history = RunnerRestartHistory()
        #expect(history.record(settings: settings, status: 0, uptime: .zero, intentional: false) == .retry(after: .seconds(10)))
        #expect(history.record(settings: settings, status: 0, uptime: .zero, intentional: false) == .quarantine)
        history = RunnerRestartHistory()
        #expect(history.record(settings: settings, status: 0, uptime: .seconds(60), intentional: false) == .retry(after: .seconds(10)))
        #expect(history.record(settings: settings, status: 0, uptime: .zero, intentional: false) == .retry(after: .seconds(10)))
    }
}
