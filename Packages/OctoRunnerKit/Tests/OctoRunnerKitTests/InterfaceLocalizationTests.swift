import AppKit
@testable import AppShellFeature
import CoreModels
import DesignSystem
import Foundation
import GitHubAPI
import RunnerEngine
import Testing

struct InterfaceLocalizationTests {
    @Test("Legacy interface strings resolve from the package in German and English", arguments: [
        ("New Runner", "Neuer Runner"),
        ("Sync Runners", "Runner abgleichen"),
        ("Sign in with GitHub", "Mit GitHub anmelden"),
        ("LOCAL WORKPOOL RUNNERS", "LOKALE RUNNER"),
        ("No local runners configured yet.", "Noch keine lokalen Runner eingerichtet."),
        ("General & Labels", "Allgemein & Labels"),
        ("Working Directory", "Arbeitsverzeichnis"),
        ("Runner Diagnostics", "Runner-Diagnose"),
        ("Filter log output…", "Log-Ausgabe filtern …"),
        ("Single Repository", "Einzelnes Repository"),
        ("Base Runner Prefix", "Präfix für Runner-Namen"),
        ("Validate & Connect", "Prüfen & verbinden"),
        ("Host CPU Architecture", "CPU-Architektur des Hosts"),
        ("Failed / Faulted", "Fehlerhafte Runner")
    ])
    func legacyStrings(_ pair: (String, String)) {
        let key = String.LocalizationValue(stringLiteral: pair.0)
        #expect(AppLocalization.string(key, locale: Locale(identifier: "de")) == pair.1)
        #expect(AppLocalization.string(key, locale: Locale(identifier: "en")) == pair.0)
    }

    @MainActor
    @Test("The native quit dialog follows the chosen app language")
    func quitDialog() {
        let german = AppQuitConfirmation.makeAlert(locale: Locale(identifier: "de"))
        #expect(german.messageText == "OctoRunner beenden?")
        #expect(german.informativeText.contains("Menüleistensymbol"))
        #expect(german.buttons.map(\.title) == ["OctoRunner beenden", "Abbrechen"])
        let english = AppQuitConfirmation.makeAlert(locale: Locale(identifier: "en"))
        #expect(english.messageText == "Quit OctoRunner?")
        #expect(english.buttons.map(\.title) == ["Quit OctoRunner", "Cancel"])
    }

    @Test("Runner status presentation follows locale without changing persisted raw values")
    func runnerStatus() {
        #expect(RunnerStatus.idle.localizedBadgeTitle(locale: Locale(identifier: "de")) == "BEREIT")
        #expect(RunnerStatus.busy.localizedBadgeTitle(locale: Locale(identifier: "de")) == "LÄUFT")
        #expect(RunnerStatus.faulted.localizedBadgeTitle(locale: Locale(identifier: "de")) == "FEHLER")
        #expect(RunnerStatus.busy.localizedBadgeTitle(locale: Locale(identifier: "en")) == "RUNNING")
        #expect(RunnerStatus.busy.rawValue == "busy")
    }

    @Test("The runner sidebar retains its English navigation label")
    func allRunnersSidebarTitle() {
        #expect(AppLocalization.string("All runners", locale: Locale(identifier: "en")) == "All Runners")
        #expect(AppLocalization.string("All runners", locale: Locale(identifier: "de")) == "Alle Runner")
    }

    @Test("Interpolated interface counts retain translated labels")
    func counts() {
        #expect(AppLocalization.string("Instances: \(3)", locale: Locale(identifier: "de")) == "Instanzen: 3")
        #expect(AppLocalization.string("Instances: \(3)", locale: Locale(identifier: "en")) == "Instances: 3")
    }
    @Test("Repository refresh failures explain the reason in the chosen language")
    func repositoryFailure() {
        let failure = WorkflowHistoryRepositoryFailure(repository: "owner/project", error: .permissionDenied)
        let german = failure.localizedMessage(locale: Locale(identifier: "de"))
        #expect(german.contains("owner/project"))
        #expect(german.contains("Actions"))
        #expect(german.contains("Token"))
        #expect(!german.contains("cannot read"))
        let english = failure.localizedMessage(locale: Locale(identifier: "en"))
        #expect(english.contains("owner/project"))
        #expect(english.contains("cannot read Actions"))
        let unavailable = WorkflowHistoryRepositoryFailure(repository: "owner/other", error: .unavailable)
        #expect(unavailable.localizedMessage(locale: Locale(identifier: "de")) != german)
        #expect(unavailable.localizedMessage(locale: Locale(identifier: "de")).contains("owner/other"))
    }

    @Test("Provisioning progress remains localized around technical filenames and counts")
    func provisioningProgress() {
        #expect(RunnerProvisioningProgress.fetchingMetadata.localizedMessage(locale: Locale(identifier: "de")).contains("Metadaten"))
        #expect(RunnerProvisioningProgress.verifyingBinary(filename: "runner-arm64.tar.gz").localizedMessage(locale: Locale(identifier: "de")).contains("runner-arm64.tar.gz"))
        #expect(RunnerProvisioningProgress.registeringInstances(count: 2).localizedMessage(locale: Locale(identifier: "de")) == "Runner-Instanzen werden eingerichtet: 2 …")
        #expect(RunnerProvisioningProgress.registeringInstances(count: 2).localizedMessage(locale: Locale(identifier: "en")) == "Provisioning runner instances: 2…")
    }

    @Test("App-owned errors use the selected language")
    func appErrors() {
        let german = Locale(identifier: "de")
        #expect(AppErrorMessage.failure(GitHubAuthError.invalidTokenOrUnauthorized).localized(locale: german) == "Das GitHub-Token ist ungültig oder abgelaufen.")
        #expect(AppErrorMessage.failure(RunnerEngineError.runnerDirectoryAlreadyExists).localized(locale: german).contains("anderen Namen"))
        #expect(AppErrorMessage.failure(GitHubAuthError.invalidHTTPStatus(502)).localized(locale: german).contains("502"))
    }

    @Test("A rate limit preserves an earlier repository failure")
    func combinedHistoryFailures() throws {
        let failure = WorkflowHistoryRepositoryFailure(repository: "owner/one", error: .permissionDenied)
        let text = try #require(WorkflowHistoryRepositoryFailure.banner(
            error: .rateLimited(until: nil), failures: [failure], locale: Locale(identifier: "en")))
        #expect(text.contains("GitHub rate limit reached"))
        #expect(text.contains("owner/one: This token cannot read Actions"))
    }

    @Test("A hidden or missing Actions resource retains the HTTP distinction")
    func notFoundHistoryMessage() {
        let failure = WorkflowHistoryRepositoryFailure(repository: "owner/one", error: .resourceNotFound)
        #expect(failure.localizedMessage(locale: Locale(identifier: "en")).contains("HTTP 404"))
    }

    @Test("Runner ownership labels follow the selected language", arguments: [true, false])
    func ownershipLabel(imported: Bool) {
        #expect(DashboardRunnerRow.ownershipLabel(imported: imported, locale: Locale(identifier: "de"))
            == AppLocalization.string(imported ? "Imported" : "Managed", locale: Locale(identifier: "de")))
        #expect(DashboardRunnerRow.ownershipLabel(imported: imported, locale: Locale(identifier: "en"))
            == (imported ? "Imported" : "Managed"))
    }

}
