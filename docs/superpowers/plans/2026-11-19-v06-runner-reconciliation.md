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
- [x] Rote Transport-/Fake-Uhr-Tests für 200/304/401/403/404/429, Pagination, Retry-After, Abbruch und Kontowechsel schreiben.
- [x] Gemeinsamen bestehenden GitHub-Transport verwenden; aktuelle API-Version offiziell prüfen. Bedingte Requests, begrenzte Parallelität und Rate-Limit-Backoff; keine Endlosschleifen pro View.
- [x] Scheduler im App-Lebenszyklus starten/stoppen; GUI-Ende bedeutet ohne separaten Agenten Ende dieses Abgleichs.

**Umsetzungsstand:** Der Runner-Einzelabruf verwendet den gemeinsamen GitHub-Transport und API-Version 2026-03-10. ETag-Cache und Rate-Limit-Backoff sind kontogetrennt. Der App-Dienst startet und stoppt mit der GUI. Eine neue Auswahlrevision entwertet laufende Abrufe, auch nach einem Wechsel zurück zum ursprünglichen Konto. Lokaler Ordnerimport und Remote-Abruf sind getrennt. Der Assistent speichert die Runner-ID beim Einrichten. Nach den Einzelabrufen prüft der Abgleich eine gemeinsame Runner-Liste für alle 404 aus demselben Repository oder derselben Organisation. Ein bestätigter ID-Treffer kann aus einer paginierten Liste kommen. Abwesenheit wird nur aus einer vollständigen Antwort auf einer Seite ohne Fortsetzung abgeleitet. Bei mehreren Seiten können Hinzufügen und Löschen während der Abfrage den Inhalt verschieben.

### Task 2: Konflikte statt Überschreiben

**Files:** Create `SyncKit/RunnerReconciler.swift`, `CoreModels/RunnerSyncConflict.swift`, `AppShellFeature/RunnerSyncConflictView.swift`; Modify IntegrationController/RunnerEntity bei nachgewiesenem Schema-Bedarf; Test `RunnerReconciliationTests.swift`.

**Interfaces:** Reine Funktion `reconcile(local:remote:)` liefert bestätigte Änderungen und explizite Konflikte, zugeordnet über Account+Scope+Remote-ID; Name allein ist keine Identität.

- [x] Rote Tests: busy/online/offline, entfernte Runner, doppelte Namen, abweichende Labels/Gruppe, alte Antwort und lokaler Aktivitätswiderspruch.
- [x] Nur gesicherte beobachtete Statusdaten übernehmen. Labelkonflikte und abweichende Gruppenmitgliedschaften anzeigen. „Remote übernehmen“ und „lokal auf GitHub anwenden“ sind für Labels getrennte bestätigte Aktionen mit Audit.
- [x] Neue Model-Properties mit Defaults, Schema-/Migrationstests und makeInMemoryContainer; keinen bisherigen Store überschreiben. UI- und Unit-Tests grün, Commit/CI-Gates.

**Umsetzungsstand:** Das Dashboard und die Runner-Einstellungen zeigen belegte Status- und Labelabweichungen mit getrenntem lokalen und GitHub-Status. Ein unbelegter HTTP 404 bleibt mehrdeutig. Fehlt die Runner-ID in einer vollständigen einseitigen Scope-Liste, zeigt OctoRunner dies an und behält den lokalen Eintrag. Beide Richtungen des Labelabgleichs brauchen eine eigene Bestätigung und protokollieren angenommene Änderungen im Audit-Log. Eine GitHub-Änderung prüft die Registrierung erneut, sendet nur benutzerdefinierte Labels und übernimmt lokal erst die geprüfte GitHub-Antwort. Während einer Migration mit offenem Recovery-Journal sind Labeländerungen gesperrt. Die Runner-Einstellungen können auch die Mitgliedschaft in der gespeicherten Gruppe per Leseabfrage prüfen. Fehlt der Runner in einer vollständigen einseitigen Mitgliederliste, zeigt die Ansicht die Abweichung an. Eine Gruppenänderung erfolgt in GitHub.

### Task 3: Gruppen, Multi-Repo und v0.6-Release

**Files:** Modify `AppShellFeature/AddRunnerWizardViewModel.swift`, `AppShellFeature/RunnerTargetLoading.swift`, `CoreModels/RunnerScopeType.swift` und bestehende Wizard-Views; Tests `RunnerWizardProvisioningTests.swift`, `GitHubPermissionTests.swift`; `docs/releases/v0.6.0.md`.

**Interfaces:** Personal Multi-Repo erzeugt getrennte Repository-Registrierungen; Organisationen können echte Runner-Gruppen verwenden. Prefix ist Namenshilfe, ein Label ist Routing, eine Gruppe ist Berechtigungs-/Organisationsstruktur.

- [x] Organisations-/Repository-Berechtigungsübersicht aus Screenshot 07c mit zugewiesenen Runner-Zahlen und explizitem „Berechtigungen abgleichen“ implementieren. Abfragen nutzen reale Gruppen- und Zieldaten. Tests prüfen fehlende Rechte, Kontowechsel und veraltete Sync-Antworten.
- [x] Screens 03 und 04 erneut abgleichen. Tests prüfen getrennte Repositories mit demselben Präfix, Gruppenabfragen, Teilfehler und Identität nach Migration.
- [x] Wizard/Modell/API konsistent verdrahten. Rechte je Endpunkt anhand aktueller GitHub-Doku prüfen. Unbekannte Token-Rechte bleiben als solche sichtbar.
- [x] Lokale Tests, Xcode-Build, Review, PR-CI und main-CI für den Funktionsstand. [PR #43](https://github.com/loesch-digital/octorunner/pull/43) · [Main-CI](https://github.com/loesch-digital/octorunner/actions/runs/44718206244)
- [ ] Versions-PR und dessen main-CI abschließen. Den geprüften Stand mit `npx release-it 0.6.0 --ci --no-npm --no-git.commit` taggen, Workflow beobachten und Brew, App-Start und Gatekeeper prüfen.

**Umsetzungsstand:** Die Berechtigungsübersicht fragt die Runner-Listen pro gespeichertem Ziel mit dem aktiven Konto ab. Sie zeigt belegten Lesezugriff sowie getrennte Zahlen für GitHub-Registrierungen und passende Runner dieses Macs. Bei Organisationen fragt sie zusätzlich die sichtbaren Gruppen ab. Der Assistent verwendet pro ausgewähltem Repository eine eigene Registrierung und meldet Teilfehler mit der Zahl der gespeicherten Runner. Organisationsgruppen stammen aus GitHub und werden vor der Registrierung erneut geprüft. Neue Registrierungen verwenden GitHubs Ersetzungsoption nicht. Die bestätigte Migration speichert die geprüfte Runner-Gruppe zusammen mit der neuen Runner-ID.
