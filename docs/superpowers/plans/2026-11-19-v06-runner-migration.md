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

- [x] Den bisherigen Kopierpfad mit Tests für den Quellordner, Symlinks, einen aktiven Listener, einen laufenden Job und fehlenden GitHub-Zugriff abgesichert.
- [x] Vorprüfung liest nur die Metadaten der gewählten Quelle. Vor der Registrierung werden Quellidentität, ruhender Listener, Labels, Account, GitHub-Ziel und gegebenenfalls die Gruppe erneut geprüft.
- [x] Beide UI-Einstiege führen zur gleichen Bestätigung. Der Dialog zeigt Betriebsart, neue Registrierung, Arbeitsordner und Wiederherstellung. NSHostingView-Tests decken Englisch und Deutsch ab.

### Task 2: Journal, Übernahme und Wiederherstellung

**Files:** Create `RunnerEngine/RunnerMigrationCoordinator.swift`, `RunnerEngine/RunnerMigrationJournal.swift`; Modify Provisioner und MigrationCompletion; Test `RunnerMigrationTransactionTests.swift`.

**Interfaces:** Coordinator `migrate(plan: RunnerMigrationPlan) async throws` liefert belegten Abschluss oder Wiederherstellungsbedarf. Journal speichert ausschließlich IDs, nicht geheime Pfade, Stufen und Resultate; Credential-Zugriff nur im bestehenden sicheren Registrierungsdienst.

- [x] Fehlergrenzen für Vorprüfung, Vorbereitung, Registrierung, Modell-Commit und Start sowie die Wiederaufnahme mit neuem Koordinator getestet. Der ursprüngliche Schlüssel bleibt im ursprünglichen Ordner. Offene Migrationen sperren beide Pfade für den Import.
- [x] Die Übernahme setzt einen gestoppten alten Listener und deaktivierten Autostart voraus. OctoRunner lehnt den noch installierten Standarddienst ab und prüft lokalen und GitHub-Status. Die neue Installation nutzt ein checksum-geprüftes Archiv und ein kurzlebiges Registrierungstoken.
- [x] Die verifizierte GitHub-ID wird vor dem Start gespeichert. OctoRunner kann vorbereitete Dateien sicher verwerfen und nach bestätigter Registrierung fortsetzen. Ein Abbruch mit unbekanntem GitHub-Ergebnis erfordert eine Prüfung in GitHub, da das Registrierungsprogramm den Austausch anhand des Namens ausführt.
- [x] SwiftData lädt die Runner-ID nach asynchronen Schritten erneut. Der Commit enthält einen Runner-bezogenen Audit-Eintrag. Das Journal zeigt bei einem Abbruch die letzte bestätigte Stufe und verfügbare Wiederherstellungsschritte.
- [ ] Grün, unabhängiges Review, Commit und CI-Gates. Nutzerabnahme mit einem entbehrlichen Runner; vorhandene produktive Runner nicht für Fehlersimulationen verwenden.
