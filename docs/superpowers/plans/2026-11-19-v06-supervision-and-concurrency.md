# v0.6 Prozessaufsicht und Parallelität Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Native Umsetzung; bestehende Nutzerfreigabe zur anschließenden Implementierung beachten.

**Goal:** Echte Start/Stop/Restart-Steuerung, Crash-Policies, Live-Logs und ein wirksames Limit für von OctoRunner verwaltete Runner liefern.

**Architecture:** Ein Supervisor-Actor besitzt den Lebenszyklus direkt verwalteter Prozesse. launchd-Betrieb wird ausdrücklich getrennt; zwei unabhängige Eigentümer dürfen niemals denselben Listener starten. Keine GitHub-Jobannahmegarantie aus einer lokalen Einstellung ableiten.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, SPM, macOS ServiceManagement; bestehende Python-/GitHub-Actions-Werkzeuge.

**Spec:** `docs/01-architecture-and-modules.md` ADR-01/03, `docs/05-step-03-runner-wizard-and-engine.md`, `docs/06-step-04-dashboard-detail-and-menubar.md`, Nutzerumfang v0.6; verbindliche Umfangsentscheidung vom 19.11.2026: globales Parallelitätslimit erst v0.6.

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

1. Gleichzeitiges Start/Stop und verspätete Exit-Callbacks dürfen keinen fremden Prozess treffen (Task 1).
2. Dauerabstürze dürfen keine Restart-Schleife erzeugen (Task 2).
3. Absenken des Limits darf aktive Jobs nicht abbrechen (Task 3).
4. Langsame Log-Consumer und Dateirotation dürfen Speicher nicht unbegrenzt wachsen lassen (Task 4).
5. GUI-Ende darf weder Headless-Fortsetzung noch aktiven Supervisor vortäuschen (Task 1/3).

### Task 1: Prozessbesitz und Steuerung

**Files:** Modify `Packages/OctoRunnerKit/Sources/RunnerEngine/RunnerSupervisorActor.swift`; Create `RunnerProcessControlling.swift`, `ManagedRunnerProcess.swift` im selben Ordner; Test `Packages/OctoRunnerKit/Tests/OctoRunnerKitTests/RunnerSupervisorTests.swift`; Modify ADR-01.

**Interfaces:** Neue Sendable-Snapshots statt SwiftData-Objekten über Actor-Grenzen. Supervisor-API: `start(runnerID: UUID) async throws`, `stop(runnerID: UUID) async throws`, `restart(runnerID: UUID) async throws`; Prozessadapter liefert identifizierbare Exit-Ereignisse pro Startgeneration.

- [x] Eigentumsmatrix für direkte Child-Prozesse, bestehende LaunchAgents und importierte externe Listener dokumentieren. Der direkte Modus übernimmt laufende fremde Listener erst nach verifizierter Migration.
- [x] Doppelstart, verspäteten Exit einer früheren Generation, abgebrochenen Start und fremde Prozesse mit Fake-Prozess-Tests abdecken.
- [x] Graceful Drain, Fristablauf und separat bestätigten erzwungenen Stopp testen. Der Quit-Dialog erklärt, welche Runner weiterlaufen. Vor freiwilligem Stopp und Quit wird der lokale Jobzustand erneut geprüft.
- [x] Direkten Prozessadapter ohne blockierendes `waitUntilExit` implementieren. Der Exit bleibt der Startgeneration zugeordnet und wird erst nach Ende der eigenen Prozessgruppe gemeldet. Native Tests verwenden kurzlebige Prüfprozesse.
- [x] App-Controls für direkte Runner mit bestätigter PID, Laufzeit, Status und Audit anbinden. Speicherbereinigung und Prozessstart verwenden eine gemeinsame Verzeichnissperre.
- [x] PR und main-CI für die direkte Prozessaufsicht vollständig grün prüfen.
- [x] LaunchAgent-Diagnose aus Screenshot 07 in Einstellungen und Runner-Details ergänzen. Die installierte Plist mit Syntaxprüfung zur Ansicht anbieten und einen entladenen, nachweislich eigenen Dienst wieder laden. Ein geladener Dienst kann weiterlaufen. Tests decken fehlende, fremde und während der Prüfung ersetzte Definitionen ab.

### Task 2: Restart, Throttle und Quarantäne

**Files:** Create `RunnerEngine/RunnerRestartScheduler.swift`; Modify `CoreModels/RunnerRuntimePolicy.swift`, `RunnerEngine/RunnerSupervisorActor.swift`, `AppShellFeature/Settings/FailoverSettingsTab.swift`; Test `RunnerRestartPolicyTests.swift` unter den bestehenden Tests.

**Interfaces:** Scheduler konsumiert Exitcode, Generation und RunnerRuntimePolicy; injizierte monotone Uhr, keine Echtzeit-Sleeps in Unit-Tests. Ergebnis: Restart-Termin oder Quarantäne; manuelle Freigabe eigener Befehl.

- [ ] Rote Tests für Always/On Non-Zero/Manual, freiwilligen Stop, Verzögerung, N Fehlversuche, Reset nach stabilem Lauf und Cancellation schreiben; Grenze N exakt testen.
- [ ] Battery Saver gegen `ProcessInfo.isLowPowerModeEnabled` testen und verdrahten: neue verwaltete Starts bei aktivierter Richtlinie zurückstellen, laufende Jobs erhalten; beim Ende des Low-Power-Modus Warteschlange wieder prüfen.
- [ ] Policies implementieren und bestehende Einstellungen wirklich für verwaltete Runner anwenden; Crash-Ereignisse mit wiederholungsarmer macOS-Mitteilung verbinden. Berechtigung nur bei Aktivierung anfordern.
- [ ] Quarantäne/Fehler/letztes Jobresultat optisch getrennt zeigen. Grün, Commit und beide CI-Gates.

### Task 3: Globales Parallelitätslimit

**Files:** Create `RunnerEngine/RunnerAdmissionController.swift`; Modify `CoreModels/AppPreferencesStore.swift`, `RunnerEngine/RunnerSupervisorActor.swift`, passende Settings-Seite; Test `RunnerAdmissionTests.swift`.

**Interfaces:** `RunnerAdmissionController` verwaltet reservierte/aktive Slots anhand stabiler Runner-IDs; Start kann nur mit gültiger Reservierung stattfinden. FIFO wartender eigener Runner, bereits aktive Jobs behalten ihren Slot bis zum sicheren Ende.

- [ ] Vor Produktionscode Architekturprobe mit zwei isolierten Test-Runnern planen: persistente Listener können zwischen Drain-Anfrage und Stop neue GitHub-Jobs erhalten. GitHub dokumentiert hierfür keine atomare Pause. Kein undokumentiertes `--once` als garantierte API behandeln.
- [ ] Vertragsgrenze explizit dokumentieren: Zahl gleichzeitig von OctoRunner gestarteter/zugelassener Runner, externe und eigenständig laufende Legacy-LaunchAgents separat anzeigen. Falls eine streng jobweise Zulassung/Headless-Garantie nur mit ephemerer Registrierung oder neuem Agenten möglich ist, konkrete ADR-Entscheidung vor diesem Teil beim Nutzer klären.
- [ ] Rote Tests: Limit 1 bei zwei gleichzeitigen Starts; fehlgeschlagener Start gibt Slot frei; Reduktion 2→1 beendet keinen aktiven Job und verhindert neue Starts; Neustart/Abbruch dupliziert keine Reservierung; wartender Runner wird nach Freigabe zugelassen.
- [ ] Admission mit Task 1/2 verbinden, gespeicherten Wert erst jetzt als wirksam anbieten. Grün, Commit und CI-Gates.

### Task 4: Live-Logs und Dialog 05

**Files:** Modify `RunnerEngine/RunnerLogStreamerActor.swift`, `AppShellFeature/RunnerConsoleLogSheet.swift`; Create `RunnerLogStreamingTests.swift` unter den Tests.

**Interfaces:** Begrenzter AsyncStream von Logzeilen; direkter Modus aus Pipes, Headless-Modus aus ereignisgesteuerter Datei-Beobachtung. Bisherige Log-Level-/Zeitstempelmodelle weiterverwenden.

- [ ] Screenshot 05 erneut ansehen. Rote Tests für geteilte UTF-8-Zeichen, stdout/stderr, begrenzten Puffer mit sichtbarem Verlusthinweis, Rotation/Truncation und Subscriber-Abbruch schreiben.
- [ ] Polling ersetzen; Suche/Level-Filter, Auto-Scroll/Pause, Kopieren/Export und Retention abgleichen. Keine Geheimnisse ungefiltert in Diagnoseexporte übernehmen.
- [ ] NSHostingView schmal/breit und Cancellation prüfen; lokale Tests, Review, Commit und CI-Gates. v0.6 noch nicht taggen: Migration und Sync folgen.

**Technische Grundlage:** [GitHub Self-hosted runner reference](https://docs.github.com/en/actions/reference/runners/self-hosted-runners): Empfehlungen für ephemere Runner und Einschränkungen persistenter Runner beim Herunterfahren. Optionaler Hintergrund-Agent ist ein gesonderter ADR und kein stiller Pflichtbestandteil dieses Plans.
