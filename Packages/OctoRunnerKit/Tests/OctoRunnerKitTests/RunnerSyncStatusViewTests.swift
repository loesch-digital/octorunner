import AppKit
@testable import AppShellFeature
import Foundation
import SwiftUI
import SyncKit
import Testing

@MainActor
struct RunnerSyncStatusViewTests {
    @Test("A runner’s GitHub status and conflict fit narrow controls in both languages and appearances")
    func conflictLayout() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let json = Data(#"{"id":22,"name":"fixture","status":"offline","busy":false,"os":"macOS","labels":[{"name":"xcode"}]}"#.utf8)
        let remote = try JSONDecoder().decode(GitHubRemoteRunnerDTO.self, from: json)
        let comparison = RunnerReconciler.compare(expectedID: 22, expectedName: "fixture", localStatus: .busy,
            localLabels: ["different"], result: .found(remote, eTag: nil))
        let observation = RunnerSyncObservation(comparison: comparison, localStatus: .busy,
            localObservedAt: date, remoteObservedAt: date)
        for locale in [Locale(identifier: "en"), Locale(identifier: "de")] {
            for scheme in [ColorScheme.light, .dark] {
                let content = RunnerSyncStatusView(observation: observation, showsDetails: true)
                    .environment(\.locale, locale)
                    .preferredColorScheme(scheme)
                    .frame(width: 250)
                let host = NSHostingView(rootView: content)
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.width == 250)
                #expect(host.fittingSize.height > 45)
                #expect(host.fittingSize.height < 250)
            }
        }
    }
}
