# GitHub-Verknüpfung und Actions-Details Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Nutzer hat native Umsetzung bereits autorisiert; keine neue allgemeine Freigabe erforderlich.

**Goal:** In Jobs den zugehörigen PR erkennen, direkt zu PR/Run/Job auf GitHub wechseln und Workflow-/Job-/Step-Zustände mit verfügbaren Logs nachvollziehen können.

**Architecture:** Bestehende accountbezogene History-Pipeline erweitern. GitHub-REST-Daten bleiben die Quelle; lokale Runner-Logs aus v0.6 sind davon getrennt. Read-only Funktionen benötigen keine neuen Schreibrechte. Kein HTML-Scraping der Actions-Webseite.

**Tech Stack:** macOS 15+, Swift 6 Strict Concurrency, SwiftUI, SwiftData, vorhandener GitHubActionsClient und Keychain-Lookup.

**Spec:** Nutzerfrage vom 19.11.2026 zur PR-Verknüpfung und Actions-Sicht; docs/07 Dialog 8, docs/assets/screens/08_jobs_workflow_runs.png, docs/12-jobs-history-and-metrics.md.

## Global Constraints

- AGENTS.md, vier Repo-Skills und relevante Referenzen vor Code beachten. Bestehende Native-/Branch-/TDD-/CI-Regeln gelten.
- Zuerst den bereits geprüften Abschlusszweig fertigstellen: keine Vermischung neuer Jobs-Produktionsänderungen mit dessen noch nicht bestandener PR-/main-CI. Dieser Plan ist eine zusätzliche v0.5-Abhängigkeit vor dem stabilen Release.
- Kein automatisches Mehrrecht für neue reine Anzeige. Rechtebedarf pro REST-Endpunkt anhand aktueller offizieller GitHub-Dokumentation prüfen; nicht aus OAuth-Scope-Headern raten.
- Keine Tokens, signierten Download-URLs oder privaten Log-Inhalte in Diagnoseausgaben/Audit schreiben. Logs nur bewusst öffnen, nicht automatisch beim Start herunterladen.
- ModelContext/Modelle bleiben auf MainActor; neue Model-Properties mit Defaults, echte Alt-Store-Migration testen und SQLite-Headerprüfung erhalten.
- Fehlende PR-Metadaten sind „nicht verfügbar“, nicht „kein PR“, sofern die API den Zusammenhang nicht sicher liefert. Push-/Dispatch-Runs benötigen keinen erfundenen PR.
- Keine pixelgenaue Kopie oder Schreibaktionen wie Rerun/Cancel implizit aus „Actions-Sicht“ ableiten. Web-Links bleiben für vollständige GitHub-Funktionen erhalten.

## Review Focus

1. Fork-PRs: falsches Repository darf keinen irreführenden PR-Link erzeugen (Task 1).
2. Neuer Run-Attempt: alte Jobs/Steps/Logs dürfen nicht dem aktuellen Versuch zugeordnet werden (Task 2/3).
3. Kontowechsel/Teardown: verspätete Antworten dürfen weder Persistenz noch UI verändern (alle Tasks).
4. Leere oder begrenzte API-Antwort: fehlende Daten dürfen nicht als erfolgreiche/leere vollständige Ausführung erscheinen (Task 2/3).
5. Große Logs oder Redirects: begrenzter Speicher, Credential-Isolation und sichtbare Kürzung statt unbeschränktem Download (Task 3).

### Task 1: PR-Bezug vom API-DTO bis zur Oberfläche

**Files:** Modify `Packages/OctoRunnerKit/Sources/GitHubAPI/GitHubWorkflowRunDTO.swift`, `Sources/CoreModels/JobRunEntity.swift`, `Sources/CoreModels/WorkflowHistoryEntry.swift`, `Sources/CoreModels/WorkflowHistoryFilter.swift`, `Sources/AppShellFeature/WorkflowHistoryStore.swift`, `Sources/AppShellFeature/WorkflowRunHistoryRow.swift`, `Sources/AppShellFeature/WorkflowHistoryPresentation.swift` (Sources jeweils unter Packages/OctoRunnerKit). Create GitHubWorkflowPullRequestDTO.swift und WorkflowPullRequestReference.swift in den passenden Modulen. Tests: neue WorkflowPullRequestTests.swift und vorhandene Decoding-/Persistence-/Layout-Tests.

**Interfaces:** `GitHubWorkflowRunDTO.pullRequests: [GitHubWorkflowPullRequestDTO]?`; Referenz enthält positive Nummer und explizites Basis-Repository. DTO -> validierte `[WorkflowPullRequestReference]` -> persistierte optionale JSON-Data mit Default nil -> unveränderlicher History-Snapshot. Validierte Links akzeptieren nur HTTPS github.com, passendes Basis-Repo und `/pull/<positive number>` ohne Userinfo/Query/Fragment.

- [ ] RED: API `pull_requests` mit PR #12, Push-Run ohne Feld, explizit leer, mehrere PRs und Fork-Head/Base dekodieren; negative Nummer/unpassender Host/Pfad werden nicht verlinkt. API-Dokumentation klärt welche Run-Antworten PRs auslassen; falls nötig gezielt Commit-PR-Lookup mit eindeutiger Zuordnung, sonst unbekannt lassen.
- [ ] RED: Persistenz-Roundtrip, gleicher Run in zwei Accounts/Attempts, Refresh und verspätete Antwort nach Kontowechsel. Bestehenden Disk-Store öffnen, Account-/Runner-Daten bleiben erhalten.
- [ ] GREEN: Referenzen ohne zusätzlichen automatischen Netzwerkaufruf durch bestehende Pipeline führen. Zeile zeigt PR #12 als Link; Branch/Commit/Trigger bleiben getrennt. Suche findet PR-Nummer. NSHostingView DE/EN Hell/Dunkel schmal/breit, lange Titel und mehrere PRs.
- [ ] Vollständige Swift-/Python-Tests, nativer App-Build, unabhängiger Review, semantischer Commit, PR-CI, Merge und main-CI vollständig grün abwarten.

### Task 2: Workflow-/Job-/Step-Detailansicht

**Files:** Modify GitHubWorkflowJobDTO.swift, GitHubActionsClient.swift und WorkflowRunHistoryRow.swift; create GitHubWorkflowStepDTO.swift (GitHubAPI), WorkflowRunDetailModel.swift, WorkflowRunDetailView.swift und WorkflowJobStepView.swift (AppShellFeature); Tests WorkflowRunDetailTests.swift plus native Navigationstest.

**Interfaces:** `GitHubWorkflowJobDTO.steps: [GitHubWorkflowStepDTO]?`; Step enthält Nummer, Name, Status, Conclusion und echte optionale Start-/Endzeiten. Detail-Selektion ist unveränderlich `(accountID, repository, runID, attempt, jobID?)`. Modell lädt Details für genau diesen Attempt, verwirft überholte Generationen und beendet Refresh bei Teardown; bestehendes RateBudget respektieren.

- [ ] RED: gemischte Step-Zustände (queued/running/succeeded/failed/skipped/cancelled/unknown), null-Zeitstempel, fehlendes steps-Feld und Attempt-Wechsel. Fehlende Zeiten erzeugen keine fiktive Dauer. Ein Jobfehler ersetzt nicht die Anzeige anderer Jobs.
- [ ] RED: Details öffnen, Job auswählen, Run/Job/PR-Weblinks sowie Tastatur-/VoiceOver-Bedienung; Teardown und Kontowechsel während Antwort verwerfen Daten. 403/404/429 und unvollständige Pagination bleiben sichtbar.
- [ ] GREEN: kompakte Run-Zusammenfassung, ausklappbare Jobs, Step-Liste mit Nummer/Status/Dauer und bestätigter Aktualität. Kein pauschales „live“ für historische oder veraltete Daten. Responsive Detailansicht statt dauerhaft eingeblendeter großer Console.
- [ ] Vollständige Tests/Build/Review/PR-/main-CI wie Task 1.

### Task 3: Verfügbare Job-Logs und v0.5-Release-Gate

**Files:** Create GitHubJobLogLoader.swift (GitHubAPI), WorkflowJobLogModel.swift und WorkflowJobLogView.swift (AppShellFeature); extend DetailView, Tests GitHubJobLogLoaderTests.swift und WorkflowJobLogTests.swift; docs/12 und docs/releases/v0.5.0.md aktualisieren.

**Interfaces:** `loadJobLog(selection: WorkflowJobLogSelection) async throws -> WorkflowJobLogSnapshot`; Snapshot enthält Text, Beobachtungszeit und `isTruncated`. Maximale Anzeige 1 MiB UTF-8, Download per begrenztem Stream statt `data(for:)` eines unbeschränkten Archivs. Job-spezifischer Endpoint nach aktueller offizieller API-Dokumentation; Redirects isolieren Authorization vom externen Downloadhost. Keine signierten URLs persistieren. Aufrufen erst nach bewusster Log-Auswahl.

- [ ] RED: 401/403, abgelaufene oder noch nicht verfügbare Logs, laufender Job, Redirect auf externen Downloadhost ohne Authorization-Weitergabe, Cancellation, verspätete Antwort, übergroßer Stream, UTF-8 über Chunkgrenze und binäre Antwort. Lokaler Stub-Server wird mit bestehender asynchroner PythonTestServer-Hilfe beendet, nie synchron auf Swift-Executor warten.
- [ ] GREEN: verfügbare Logs lesbar/selektierbar; explizit „noch nicht verfügbar“, „gekürzt“ und „zuletzt geladen“ anzeigen. Kein vorgetäuschter REST-Live-Stream. Direkter Actions-Link als funktionierender Fallback, kein stiller Empty-State bei Fehler.
- [ ] Snapshot-/Hosting-Tests mit langen Zeilen und schmalem Fenster; native Auswahltest. Kein automatischer Download/Export privater Logs. Lokales Runner-Livestreaming bleibt v0.6.
- [ ] Vollständige Tests, Build, Review, PR-/main-CI; erst danach Task 2 des v0.5-Abschlussplans (Release) zulassen. Release-Notizen und Abnahmematrix nennen PR-/Step-/Log-Funktionen nur nach tatsächlicher Integration.
