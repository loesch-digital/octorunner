import AppKit
import CoreModels
import Foundation
import SecurityKit
import SwiftData
import SwiftUI
import Testing
@testable import AppShellFeature

@MainActor
struct AuthSettingsTests {
    private static var containers: [ModelContainer] = []

    @Test("Auth settings render empty and many-account states in both languages and appearances without credential access")
    func rendersWithoutCredentialAccess() async throws {
        for count in [0, 80] {
            let container = try OctoRunnerPersistence.makeInMemoryContainer()
            Self.containers.append(container)
            for index in 0..<count {
                let number = index + 1
                let account = GitHubAccountEntity(githubUserId: Int64(number), login: "account-\(number)-with-a-long-name",
                    displayName: String(repeating: "Long display name ", count: 10),
                    scopes: number.isMultiple(of: 2) ? [] : ["repo", "read:org", String(repeating: "long-scope-", count: 20)],
                    keychainAccountKey: "fixture-\(number)", isActive: number == 1)
                container.mainContext.insert(account)
            }
            try container.mainContext.save()
            let secrets = AuthSettingsSecrets()
            let session = AccountSessionController(secrets: secrets)
            for language in [AppLanguage.german, .english] {
                for scheme in [ColorScheme.light, .dark] {
                    for width in [620.0, 900.0] {
                        let host = NSHostingView(rootView: SecurityTokenSettingsTab(accountSession: session)
                            .modelContainer(container).environment(\.locale, language.locale).preferredColorScheme(scheme))
                        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                        host.frame = CGRect(x: 0, y: 0, width: width, height: 520)
                        host.layoutSubtreeIfNeeded()
                        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
                        if let directory = ProcessInfo.processInfo.environment["OCTORUNNER_LAYOUT_CAPTURE_DIR"] {
                            let name = "auth-\(count)-\(Int(width))-\(language.rawValue)-\(scheme == .dark ? "dark" : "light").png"
                            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appending(path: name))
                        }
                    }
                }
            }
            #expect(await secrets.deletions == 0)
            #expect(try container.mainContext.fetchCount(FetchDescriptor<GitHubAccountEntity>()) == count)
            #expect(try container.mainContext.fetchCount(FetchDescriptor<AuditLogEntity>()) == 0)
        }
    }

    @Test("Auth settings present a safe retry state after a credential deletion failure")
    func rendersError() async throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.containers.append(container)
        let account = GitHubAccountEntity(githubUserId: 7, login: "fixture", keychainAccountKey: "fixture")
        container.mainContext.insert(account)
        try container.mainContext.save()
        let secrets = AuthSettingsSecrets(fails: true)
        let session = AccountSessionController(secrets: secrets)
        #expect(!(await session.disconnect(accountID: account.id, in: container.mainContext)))
        let host = NSHostingView(rootView: SecurityTokenSettingsTab(accountSession: session)
            .modelContainer(container).environment(\.locale, Locale(identifier: "de")))
        host.frame = CGRect(x: 0, y: 0, width: 620, height: 520)
        host.layoutSubtreeIfNeeded()
        #expect(host.bitmapImageRepForCachingDisplay(in: host.bounds) != nil)
        #expect(session.error == .credentialDeletionFailed)
        #expect(await secrets.deletions == 1)
        #expect(account.isActive)
    }
}

private actor AuthSettingsSecrets: SecretDeleting {
    private(set) var deletions = 0
    let fails: Bool
    init(fails: Bool = false) { self.fails = fails }
    func deleteSecret(account: String, category: String) async throws {
        deletions += 1
        if fails { throw KeychainError.interactionNotAllowed }
    }
}
