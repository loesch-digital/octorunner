import Foundation
import GitHubAPI
import Observation

@MainActor
@Observable
final class SettingsUpdateController {
    let currentVersion: String
    private(set) var isChecking = false
    private(set) var checkFailed = false
    private(set) var info: AppUpdateInfo?
    @ObservationIgnored private let checker: @Sendable (String) async throws -> AppUpdateInfo

    init(
        currentVersion: String = AppUpdaterActor.currentBundleVersion,
        checker: @escaping @Sendable (String) async throws -> AppUpdateInfo = { version in
            try await AppUpdaterActor().checkForUpdates(currentVersion: version)
        }
    ) {
        self.currentVersion = currentVersion
        self.checker = checker
    }

    func checkForUpdates() async {
        guard !isChecking, !Task.isCancelled else { return }
        isChecking = true
        checkFailed = false
        info = nil
        defer { isChecking = false }
        do {
            let result = try await checker(currentVersion)
            guard !Task.isCancelled else { return }
            info = result
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            checkFailed = true
        }
    }
}
