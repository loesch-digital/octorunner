import CoreModels
import Foundation
import SwiftData
import SwiftUI

@MainActor
struct DashboardPreview: View {
    let container: ModelContainer
    let language: AppLanguage

    var body: some View {
        MainShellView()
            .modelContainer(container)
            .environment(\.usesDashboardSampleData, true)
            .environment(\.locale, language.locale)
            .allowsHitTesting(false)
    }

    static func makeContainer() throws -> ModelContainer {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(GitHubAccountEntity(
            githubUserId: 1, login: "build-example", displayName: "Build Example",
            scopes: [], keychainAccountKey: ""
        ))
        let samples: [(String, String, RunnerStatus, [String])] = [
            ("mac-studio-1", "mobile", .busy, ["self-hosted", "macOS", "ARM64", "ios"]),
            ("mac-studio-2", "mobile", .idle, ["self-hosted", "macOS", "ARM64", "ios"]),
            ("mac-mini-1", "desktop", .offline, ["self-hosted", "macOS", "ARM64"])
        ]
        for (name, repository, status, labels) in samples {
            let root = URL(filePath: "/tmp/octorunner-preview/\(name)")
            let runner = RunnerEntity(
                name: name, scopeUrl: URL(string: "https://github.com/build-example/\(repository)")!,
                status: status, labels: labels, workDirectory: root.appending(path: "_work"),
                executionMode: .external
            )
            if status == .busy {
                runner.currentJobName = "Build and Test"
                runner.currentRepo = "build-example/\(repository)"
            }
            context.insert(runner)
        }
        try context.save()
        return container
    }
}

#if DEBUG
#Preview("Dashboard · English · Dark") {
    if let container = try? DashboardPreview.makeContainer() {
        DashboardPreview(container: container, language: .english)
            .frame(width: 1120, height: 740)
            .preferredColorScheme(.dark)
    }
}

#Preview("Dashboard · Deutsch · Hell") {
    if let container = try? DashboardPreview.makeContainer() {
        DashboardPreview(container: container, language: .german)
            .frame(width: 960, height: 620)
            .preferredColorScheme(.light)
    }
}
#endif
