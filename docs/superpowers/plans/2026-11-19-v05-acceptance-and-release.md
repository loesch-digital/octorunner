# v0.5 Abschluss und Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Native Umsetzung; bestehende Nutzerfreigabe zur anschließenden Implementierung beachten.

**Goal:** Vorhandene v0.5-Funktionen vollständig abnehmen und erst danach v0.5.0 signiert veröffentlichen.

**Architecture:** Bestehende Module bleiben erhalten. Der Abschluss prüft wirksame Einstellungen und belegbare Funktionen; Prozessaufsicht und globale Parallelität gehören zu v0.6.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, SPM, macOS ServiceManagement; bestehende Python-/GitHub-Actions-Werkzeuge.

**Spec:** `docs/07-step-05-settings-telemetry-and-jobs.md`, `docs/release-signing.md`, `docs/18-remaining-delivery-plan.md` (verlinkt die Detailkonzepte 11–17); verbindliche Umfangsentscheidung vom 19.11.2026: globales Parallelitätslimit erst v0.6.

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

1. Persistierte Einstellung ohne Wirkung: Wirksamkeit oder ehrliche Einschränkung im Test belegen (Task 1).
2. Kontowechsel während einer API-Antwort: keine Daten des alten Kontos anzeigen (Task 1).
3. Leerer Filter bei registrierten Runnern: passender Filter-Empty-State (Task 1).
4. Fensterabbau während einer Messung: keine fortgesetzten Modellzugriffe (Task 1).
5. Installations-/Updatefehler: keine erfolgreichen Release-Behauptungen ohne Gatekeeper-/Brew-Prüfung (Task 2).

### Task 1: Abnahmematrix und gezielte Lückenschließung

**Files:** `docs/18-remaining-delivery-plan.md`, `docs/07-step-05-settings-telemetry-and-jobs.md`, `docs/17-host-telemetry.md`; bestehende `Packages/OctoRunnerKit/Tests/OctoRunnerKitTests/{SettingsTests,AppPreferencesTests,WorkflowHistoryLoadingTests,RunnerFilterRegressionTests,HostTelemetryDashboardTests,AuditLogDialogTests}.swift`.

**Interfaces:** Verwendet vorhandene Settings Scene/AppPreferencesStore, Jobs-Historie, AuditLogEntity und TelemetryKit; keine neue Engine-Schnittstelle.

- [ ] Vor dem Abschluss den im Arbeitsindex erfassten Watchdog-EOF-Folgepunkt als eigenen Bugfix rot/grün abarbeiten: stdout geschlossen bei lebendem Kind darf keine CPU-Schleife auslösen; Deadline/Exitcode/Cleanup bleiben erhalten.
- [ ] Screens 07, 07c, 07d, 07e, 08 und 09 mit implementierten Hauptfunktionen abgleichen; je Anforderung „vorhanden“, „begründet angepasst“ oder „offen“ mit Code/Test-Beleg eintragen. Parallelität verbindlich v0.6 zuordnen.
- [ ] Coverage-Lücken und triviale Assertions aus dem Arbeitsindex prüfen; echte fehlende Settings-/Lifecycle-Verhaltenstests ergänzen, vorhandene native UI-Tests als getrennte Evidenz ausweisen. Kein pauschales „alles abgedeckt“ aus dem SPM-Prozentwert ableiten.
- [ ] Vorhandene Tests den fünf Review-Fällen zuordnen. Für jede echte Lücke zuerst einen benannten roten Test ergänzen, dann nur die betroffene Implementierung korrigieren. Bestehende Tests nicht unnötig duplizieren.
- [ ] Verifizieren: Login-Item, Dock, Sprache, Shell/Retention und neue LaunchAgent-Policies wirken im dokumentierten Umfang; Crash-Benachrichtigungen bleiben bis zur echten Engine deaktiviert. Keine fiktiven Token-Ablaufdaten, SLA oder P-/E-Lastdaten ergänzen.
- [ ] Vollständige lokale Tests plus nativen App-Build ausführen; höchstens drei manuelle Abnahmen bündeln: Einstellungen, Jobs/Audit-Filter, Telemetrie/Resize. Frühere Nutzerabnahmen als Evidenz erhalten.
- [ ] Abnahmematrix und erforderliche Korrekturen semantisch committen; PR-/main-CI abwarten.

### Task 2: Signiertes v0.5.0 liefern

**Files:** Release-Versionierung gemäß vorhandener release-it-Konfiguration, `docs/releases/v0.5.0.md`, `docs/10-development-and-acceptance.md`.

**Interfaces:** Konsumiert grünen main-Commit aus Task 1 und den ergänzten Plan `2026-11-19-workflow-github-details.md` (Nutzerfrage vom 19.11.; PR-/Step-/Log-Ansicht noch nicht implementiert); liefert unveränderliches Tag und signiertes/notarisiertes App-ZIP plus Homebrew-Cask.

- [ ] Aktuelle Releases, Toolchain und offene CI-Läufe prüfen; Release Notes enthalten Features, belegte Einschränkungen und den verschobenen Parallelitätsumfang.
- [ ] Erst nach grüner main-CI `npx release-it 0.5.0 --ci` ausführen; vollständigen Release-Lauf einschließlich Tap bis zum Abschluss beobachten.
- [ ] `brew update && brew upgrade --cask octorunner`, App-Start und `spctl --assess --type execute -vv /Applications/OctoRunner.app` prüfen. ZIP-Abnahme ohne Homebrew nach docs/10 ebenfalls verfügbar halten.
- [ ] Bei Fehler Logs auswerten, Korrektur per PR und neues Patch-Tag; veröffentlichtes Archiv niemals ersetzen. Deutsche Zusammenfassung mit CI-/Release-Links und maximal drei manuellen Prüfpunkten liefern.
