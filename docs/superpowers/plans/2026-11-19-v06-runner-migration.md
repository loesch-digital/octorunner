# v0.6 Sichere Runner-Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Native Umsetzung; bestehende Nutzerfreigabe zur anschließenden Implementierung beachten.

**Goal:** Importierte Runner nach bestätigter, nachvollziehbarer Migration vollständig übernehmen und bei Fehlern einen ehrlichen Wiederherstellungszustand zeigen.

**Architecture:** Eine journalisierte Zustandsmaschine trennt Prüfung, Stop, neue Registrierung, Start und Commit. Dateisystem-Rollback und GitHub-Kompensation sind unterschiedliche Schritte; private Runner-Schlüssel werden nicht kopiert.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, SPM, macOS ServiceManagement; bestehende Python-/GitHub-Actions-Werkzeuge.

**Spec:** `docs/08-sync-kit-and-local-runner-import.md`, ADR-01, v0.6-Supervisor-Plan; verbindliche Umfangsentscheidung vom 19.11.2026: globales Parallelitätslimit erst v0.6.

## Global Constraints

Pfadkonvention: Quellpfade wie `RunnerEngine/...` oder `CoreModels/...` liegen unter `Packages/OctoRunnerKit/Sources/`; Testdateinamen liegen unter `Packages/OctoRunnerKit/Tests/OctoRunnerKitTests/`. Neue Dateien werden jeweils dort angelegt.

- macOS 15+, Swift 6 Strict Concurrency, SwiftUI und SwiftData; keine Versionsanhebung durch das CI-Image.
- Vor Änderungen die vier Repo-Skills und einschlägigen `references/*.md` lesen. `AGENTS.md` gilt uneingeschränkt.
- Jede Produktionsänderung beginnt mit einem nachweislich roten Regressionstest; anschließend grün und Refactor. Swift: `swift test --package-path Packages/OctoRunnerKit --no-parallel`; Python: `python3 -m unittest discover -s scripts/tests`.
- Feature-Branch, semantische Commits, PR. Nach Push PR-CI vollständig grün abwarten, dann Merge und main-CI vollständig grün abwarten. Keine überlappende nächste Feature-Umsetzung bei roter/laufender CI.
- Keine Secrets in Logs, Modellen oder Exporten; keine vorsorgliche Dokumente-Abfrage. SwiftData-Defaults, SQLite-Headerprüfung und Cancellation vor Modellzugriffen beibehalten.
- Neue Controls: Label/Hint, Tastaturbedienung, OctoTheme; WCAG 2.2 AA in Hell/Dunkel. NSHostingView für schmale/breite Ansichten, DE/EN.
- Konkrete Werkzeug-/API-Versionen unmittelbar vor Änderung anhand offizieller Quellen verifizieren.

## Review Focus

1. Busy-Runner: kein Jobabbruch ohne ausdrückliche Entscheidung (Task 1).
2. Symlink-/Quellpfadänderung: keine Übernahme fremder Dateien (Task 1).
3. `.credentials_rsaparams`: niemals lesen, kopieren oder exportieren (Task 1/2).
4. Fehler nach GitHub-Registrierung: ehrliche Server-Kompensation statt behauptetem Rollback (Task 2).
5. App-Absturz zwischen Schritten: Wiederaufnahme ohne Doppel-Listener (Task 2).

### Task 1: Preflight und Bestätigung

**Files:** Modify `RunnerEngine/RunnerProvisionerActor.swift`, `AppShellFeature/RunnerMigrationCompletion.swift`; Create `RunnerEngine/RunnerMigrationPlan.swift`, `AppShellFeature/RunnerMigrationConfirmation.swift`; Test bestehende `RunnerMigrationSafetyTests.swift`, `RunnerMigrationCompletionTests.swift`.

**Interfaces:** Unveränderlicher MigrationPlan enthält Runner-ID, geprüfte Quelle/Ziel, Account/Scope, Labels/Gruppe und Auswirkungen; keine Credentials. Verwendet Supervisor aus dem vorausgehenden Plan.

- [ ] Bestehenden Kopierpfad gegen das Credential-Verbot aus docs/08 prüfen. Rote Tests für enthaltene RSA-Datei, Symlinktausch, fremden Listener, Busy-Runner und verlorenen GitHub-Zugriff ergänzen.
- [ ] Preflight rein lesend auf bewusst gewählter Quelle; Quellidentität vor Mutation erneut prüfen. Labels, Account und Organisation-/Repository-Ziel mit GitHub vergleichen; Konflikte nicht automatisch überstimmen.
- [ ] Bestätigungsdialog mit alter/neuer Betriebsart, Jobauswirkung und Wiederherstellung anzeigen; keine Mutation vor Bestätigung. UI-/Unit-Tests grün, Commit/CI-Gates.

### Task 2: Journal, Übernahme und Wiederherstellung

**Files:** Create `RunnerEngine/RunnerMigrationCoordinator.swift`, `RunnerEngine/RunnerMigrationJournal.swift`; Modify Provisioner und MigrationCompletion; Test `RunnerMigrationTransactionTests.swift`.

**Interfaces:** Coordinator `migrate(plan: RunnerMigrationPlan) async throws` liefert belegten Abschluss oder Wiederherstellungsbedarf. Journal speichert ausschließlich IDs, nicht geheime Pfade, Stufen und Resultate; Credential-Zugriff nur im bestehenden sicheren Registrierungsdienst.

- [ ] Rote Failure-Injection-Tests an jeder Grenze: Stop, Staging, Registration, Start, Modell-Commit; zusätzlich Prozessabsturz und erneuter Start. Assert: höchstens ein Listener und keine RSA-Kopie.
- [ ] Alten Listener identitätsgeprüft stoppen; frische verifizierte Binary und kurzlebiges Registrierungstoken statt privater Schlüsselkopie nutzen. Alte Installation bis zum bestätigten Abschluss erhalten.
- [ ] Bei neu erzeugter Remote-ID Modell explizit aktualisieren. Falls alte Credentials serverseitig ungültig wurden, Rückregistrierung als eigene Kompensation prüfen; nicht behaupten, Dateirückkopie allein repariere GitHub.
- [ ] Nach await Modell erneut laden, Cancellation beachten, Audit mit Runner-Namen und tatsächlichen Stufen/Fehlern. Wiederherstellungsdialog nach unvollständigem Journal anbieten.
- [ ] Grün, unabhängiges Review, Commit und CI-Gates. Nutzerabnahme mit einem entbehrlichen Runner; vorhandene produktive Runner nicht für Fehlersimulationen verwenden.
