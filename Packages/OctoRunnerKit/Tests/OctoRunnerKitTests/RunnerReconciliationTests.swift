import CoreModels
import Foundation
import SyncKit
import Testing

struct RunnerReconciliationTests {
    @Test("The local process and GitHub job status remain independently visible",
          arguments: [
            ("online", false, RunnerStatus.idle, false),
            ("online", true, .busy, false),
            ("offline", false, .offline, false),
            ("offline", false, .busy, true),
            ("online", true, .idle, true),
            ("online", false, .restarting, false)
          ])
    func comparesStatus(_ status: String, _ busy: Bool, _ local: RunnerStatus, _ differs: Bool) throws {
        let remote = try runner(status: status, busy: busy)
        let result = RunnerReconciler.compare(
            expectedID: 22, expectedName: "fixture", localStatus: local, localLabels: ["xcode"],
            result: .found(remote, eTag: nil)
        )

        let expected: RunnerStatus = status == "offline" ? .offline : busy ? .busy : .idle
        #expect(result.presence == .reported(expected))
        #expect(result.hasStatusConflict == differs)
        #expect(!result.hasLabelConflict)
    }

    @Test("A hidden GitHub registration is distinct from a confirmed local or remote outage")
    func inaccessibleRegistration() {
        let result = RunnerReconciler.compare(
            expectedID: 22, expectedName: "fixture", localStatus: .idle, localLabels: [],
            result: .notFound
        )
        #expect(result.presence == .notFound)
        #expect(!result.hasStatusConflict)
    }

    @Test("Label comparisons ignore case and report a verified difference without rewriting the local value")
    func comparesLabels() throws {
        let remote = try runner(status: "online", busy: false)
        let matching = RunnerReconciler.compare(expectedID: 22, expectedName: "fixture",
            localStatus: .idle, localLabels: ["XCODE"], result: .found(remote, eTag: nil))
        let differing = RunnerReconciler.compare(expectedID: 22, expectedName: "fixture",
            localStatus: .idle, localLabels: ["custom"], result: .found(remote, eTag: nil))
        #expect(!matching.hasLabelConflict)
        #expect(differing.hasLabelConflict)
    }

    @Test("A response from another registration cannot affect this runner")
    func verifiesIdentity() throws {
        let result = RunnerReconciler.compare(
            expectedID: 23, expectedName: "fixture", localStatus: .idle, localLabels: [],
            result: .found(try runner(status: "online", busy: false), eTag: nil)
        )
        #expect(result.presence == .differentRegistration)
        #expect(!result.hasStatusConflict)
        #expect(!result.hasLabelConflict)
    }

    private func runner(status: String, busy: Bool) throws -> GitHubRemoteRunnerDTO {
        let json = """
        {"id":22,"name":"fixture","status":"\(status)","busy":\(busy),"os":"macOS","labels":[{"name":"xcode"}]}
        """
        return try JSONDecoder().decode(GitHubRemoteRunnerDTO.self, from: Data(json.utf8))
    }
}
