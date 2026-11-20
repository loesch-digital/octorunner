# v0.6 Periodischer GitHub-Abgleich Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Native Umsetzung; bestehende Nutzerfreigabe zur anschließenden Implementierung beachten.

**Goal:** Lokale und entfernte Runner periodisch kontogetrennt abgleichen und echte Konflikte sichtbar auflösen.

**Architecture:** SyncKit erzeugt unveränderliche Snapshots und einen reinen Reconciliation-Plan. SwiftData wird erst nach Account-/Generationsprüfung am MainActor aktualisiert; schreibende GitHub-Aktionen bleiben explizit.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, SPM, macOS ServiceManagement; bestehende Python-/GitHub-Actions-Werkzeuge.

**Spec:** `docs/08-sync-kit-and-local-runner-import.md`, ADR-05, `docs/09-pipeline-privacy-and-test-audit.md`, v0.6-Engine und Migration; verbindliche Umfangsentscheidung vom 19.11.2026: globales Parallelitätslimit erst v0.6.

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

1. 401/403/404/429 sind keine austauschbaren „Runner entfernt“-Zustände (Task 1).
2. Verspätete Antwort nach Kontowechsel darf nichts überschreiben (Task 1).
3. Lokaler Prozess aktiv, GitHub offline: Konflikt samt Zeitstempeln anzeigen (Task 2).
4. Name identisch, Remote-ID/Repo verschieden: keine falsche Zuordnung (Task 2).
5. Rechte fehlen oder Multi-Repo nur teilweise erfolgreich: Teilerfolg erhalten (Task 3).

### Task 1: Typisierte API-Ergebnisse und Lebenszyklus

**Files:** Modify `SyncKit/GitHubRunnerSyncActor.swift`, `SyncKit/SyncModels.swift`; Create `SyncKit/RunnerSyncScheduler.swift`; Test `RunnerSyncSchedulingTests.swift` und bestehende `SyncKitTests.swift`.

**Interfaces:** Typisierte Ergebnisse für found/notFound/unauthorized/forbidden/rateLimited/unavailable; Snapshot trägt Account-ID, Generation und Messzeit. Keine `try?`-Zusammenfassung aller Fehler zu nil.

- [x] Transport-/Decoding-Tests für `GitHubRunnerProvisioningAPI.swift` ergänzen: Repository-/Org-Endpoints, kurzlebiges Registrierungstoken, fehlende Rechte, Fehler ohne Response-Body-/Secret-Ausgabe. Die bisherige niedrige Coverage nicht durch reine DTO-Konstruktion kaschieren.
- [ ] Rote URLProtocol-/Fake-Uhr-Tests für 200/304/401/403/404/429, Pagination, Retry-After, Abbruch und Kontowechsel schreiben.
- [ ] Gemeinsamen bestehenden GitHub-Transport verwenden; aktuelle API-Version offiziell prüfen. Bedingte Requests, begrenzte Parallelität und Rate-Limit-Backoff; keine Endlosschleifen pro View.
- [ ] Scheduler im App-Lebenszyklus starten/stoppen; GUI-Ende bedeutet ohne separaten Agenten Ende dieses Abgleichs. Grün, Commit und CI-Gates.

**Umsetzungsstand:** Der Runner-Einzelabruf verwendet den gemeinsamen GitHub-Transport und API-Version 2026-03-10. ETag-Cache und Rate-Limit-Backoff sind kontogetrennt. Der App-Dienst startet und stoppt mit der GUI und verwirft Snapshots, wenn sich Auswahl oder Runner-Registrierung während der Anfrage ändern. Paginierte Scope- und Gruppenlisten, vollständige Konfliktanzeige und deren explizite Aktionen folgen in den nächsten Aufgaben.

### Task 2: Konflikte statt Überschreiben

**Files:** Create `SyncKit/RunnerReconciler.swift`, `CoreModels/RunnerSyncConflict.swift`, `AppShellFeature/RunnerSyncConflictView.swift`; Modify IntegrationController/RunnerEntity bei nachgewiesenem Schema-Bedarf; Test `RunnerReconciliationTests.swift`.

**Interfaces:** Reine Funktion `reconcile(local:remote:)` liefert bestätigte Änderungen und explizite Konflikte, zugeordnet über Account+Scope+Remote-ID; Name allein ist keine Identität.

- [ ] Rote Tests: busy/online/offline, entfernte Runner, doppelte Namen, abweichende Labels/Gruppe, alte Antwort und lokaler Aktivitätswiderspruch.
- [ ] Nur gesicherte beobachtete Statusdaten übernehmen; Labels/Gruppe bei Konflikt mit lokaler und entfernter Sicht zeigen. „Remote übernehmen“ und „lokal auf GitHub anwenden“ sind getrennte bestätigte Aktionen mit Audit.
- [ ] Neue Model-Properties mit Defaults, Schema-/Migrationstests und makeInMemoryContainer; keinen bisherigen Store überschreiben. UI- und Unit-Tests grün, Commit/CI-Gates.

### Task 3: Gruppen, Multi-Repo und v0.6-Release

**Files:** Modify `AppShellFeature/AddRunnerWizardViewModel.swift`, `AppShellFeature/RunnerTargetLoading.swift`, `CoreModels/RunnerScopeType.swift` und bestehende Wizard-Views; Tests `RunnerWizardProvisioningTests.swift`, `GitHubPermissionTests.swift`; `docs/releases/v0.6.0.md`.

**Interfaces:** Personal Multi-Repo erzeugt getrennte Repository-Registrierungen; Organisationen können echte Runner-Gruppen verwenden. Prefix ist Namenshilfe, ein Label ist Routing, eine Gruppe ist Berechtigungs-/Organisationsstruktur.

- [ ] Organisations-/Repository-Berechtigungsübersicht aus Screenshot 07c mit zugewiesenen Runner-Zahlen und explizitem „Berechtigungen abgleichen“ implementieren; reale Gruppen-/Scope-Daten statt Ableitung aus OAuth-Scopes. Rote Tests für fehlende Rechte, Kontowechsel und veraltete Sync-Antworten.
- [ ] Screens 03 und 04 erneut abgleichen. Rote Tests für zwei Repos mit gleichem Prefix, Org-Gruppen ohne Berechtigung, Teilfehler und Identität nach Migration.
- [ ] Wizard/Modell/API konsistent verdrahten, keine erfundenen Personal-Account-Runner. Rechte je Endpunkt anhand aktueller GitHub-Doku prüfen; nur tatsächlich benötigte Rechte anfordern, fehlende Fine-grained-PAT-Scope-Header bleiben „unbekannt“.
- [ ] Alle drei v0.6-Pläne einschließlich Parallelität abnehmen, vollständige lokale Tests/Build/Review, grüne PR-/main-CI. Dann `npx release-it 0.6.0 --ci`, Release vollständig beobachten, Brew/App/Gatekeeper prüfen und deutsche Abnahmezusammenfassung liefern.
