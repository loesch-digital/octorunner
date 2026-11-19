# Restliche Umsetzung bis v0.7

Stand: 19. November 2026. Dies ist der aktuelle Arbeitsindex; ältere Detailpläne dokumentieren teilweise frühere Zwischenstände und bleiben als Historie erhalten.

## Verbindlicher Umfang

Der Nutzer hat am 19.11.2026 entschieden: **Das globale Runner-Parallelitätslimit wird nach v0.6 verschoben.** Es blockiert v0.5 nicht mehr. Ein gespeicherter Wert ist bis zur Engine-Integration keine wirksame Begrenzung und darf nicht als solche dargestellt werden.

| Reihenfolge | Liefergegenstand | Plan / Abhängigkeit |
|---|---|---|
| 0 | Nachgewiesene Hänger beheben, Diagnose sichern | [CI-Testdiagnose](./superpowers/plans/2026-11-14-ci-test-diagnostics.md); PR #27–29 gemergt, aktuelle main-CI grün |
| 1 | v0.5 abnehmen und signiert veröffentlichen | [v0.5 Abschluss](./superpowers/plans/2026-11-19-v05-acceptance-and-release.md) |
| 2 | Prozessbesitz, Start/Stop/Restart, Policies, Parallelität und Live-Logs | [v0.6 Engine](./superpowers/plans/2026-11-19-v06-supervision-and-concurrency.md); benötigt 1 |
| 3 | Sichere Migration inklusive Fehlerwiederherstellung | [v0.6 Migration](./superpowers/plans/2026-11-19-v06-runner-migration.md); benötigt 2 |
| 4 | Periodischer Abgleich, Konflikte, Gruppen/Multi-Repo und v0.6-Release | [v0.6 Sync](./superpowers/plans/2026-11-19-v06-runner-reconciliation.md); benötigt 2/3 |
| 5 | Vollständige DE/EN-/Accessibility-Abnahme, Update-Rückfall, Doku und v0.7-Release | [v0.7 Politur](./superpowers/plans/2026-11-19-v07-polish-and-release.md); benötigt 4 |

## Belegter Zwischenstand

- Letzter stabiler veröffentlichter Stand: **v0.4.4**. Vorabversion: **v0.5.0-beta.2**; sie enthält die danach gemergten Ergänzungen noch nicht vollständig. Ein neuer Release wird erst nach aktueller Prüfung behauptet.
- v0.5-Implementierungen vorhanden: sechs Settings-Seiten, native konfigurierbare macOS-Mitteilungen, Menülogo mit Gesundheitsstatus, Running in Blau, getrenntes letztes Jobresultat, Jobs-Historie/-Filter/-Kennzahlen, Cache-/Speicheranalyse und sichere Bereinigung, Audit-Dialog mit Runner-Dropdown, Host-Telemetrie einschließlich Prozessinspektor, Speicherdruck und thermischem Zustand.
- Die vollständige lokale Swift-Suite umfasst beim CI-Diagnose-Fix **282 Tests in 60 Suites**. Dies belegt bestandene Tests, keine pauschale vollständige Testabdeckung. Die Abnahmematrix im v0.5-Plan prüft verbleibende Lücken.
- [PR #25](https://github.com/loesch-digital/octorunner/pull/25) lieferte den Prozessinspektor; [PR #26](https://github.com/loesch-digital/octorunner/pull/26) Speicherdruck/Thermal State. Die anschließende main-CI blieb während der Tests stehen; die zuletzt ausgegebene Testzeile identifiziert wegen gepufferter Ausgabe nicht sicher den betroffenen Test. PR-CI 44462124714 reproduzierte den Stillstand am 19.11.; ein lokaler Gesamtlauf mit drei Wiederholungen reproduzierte anschließend einen Stillstand. Die erste Stack-Aufnahme zeigt den wartenden SwiftPM-Elternprozess, die Diagnose wurde deshalb auf dessen private Testsitzung erweitert. Die tatsächliche Test-Helper-Aufnahme des lokalen Stillstands zeigt `GitHubActionsTransportTests.swift:19`: synchrones `Process.waitUntilExit()` im Aufräumen eines HTTP-Testservers. Der Zusammenhang mit dem ursprünglichen CI-Stillstand ist ohne dessen Helper-Stack noch nicht bewiesen.
- [PR #27](https://github.com/loesch-digital/octorunner/pull/27) ergänzt begrenzte Testlaufzeit und Stack-Artefakte. PR-CI [44463655972](https://github.com/loesch-digital/octorunner/actions/runs/44463655972) und main-CI [44464836288](https://github.com/loesch-digital/octorunner/actions/runs/44464836288) sind vollständig grün. Ein grüner Lauf allein beweist nicht, dass die ursprüngliche Hängerursache behoben ist. Der Prozess-Lifecycle-Fix wurde als PR #28 gemergt; 286 Tests mit je drei Wiederholungen und PR-CI waren grün. Die main-CI 44467709824 bestand die Swift-Suite, zeigte aber einen getrennten Fehler beim ersten nativen UI-Start: vorzeitiger Wechsel zur accessory-Dock-Policy vor dem ersten Fenster. Dieser zweite Fehler wurde als [PR #29](https://github.com/loesch-digital/octorunner/pull/29) mit rotem Zustandsregressionstest korrigiert. PR-CI 44469664743 und [main-CI 44470817545](https://github.com/loesch-digital/octorunner/actions/runs/44470817545) sind vollständig grün, einschließlich nativer UI-Tests. Die aktuelle lokale Suite umfasst 287 Tests. Der Nutzer hat klargestellt, dass sich die sporadischen Hänger auf GitHub-Testläufe beziehen.

## Begründete Grenzen statt Platzhalterfunktionen

- Crash-/Quarantäne-Mitteilungen werden erst mit echter Prozessaufsicht aktiviert. Keine scheinbar wirksamen Laufzeitschalter.
- Jobs-Metriken beziehen sich auf tatsächlich geladene Historie; keine erfundene vollständige GitHub-SLA.
- Telemetrie zeigt echte verfügbare Messwerte; keine geschätzte P-/E-Core-Auslastung oder unbelegte Prozesszuordnung.
- Personal Multi-Repo bedeutet mehrere Repository-Registrierungen. Prefix benennt Runner, Labels steuern Routing, Organisationsgruppen steuern Zugriff; diese Konzepte bleiben getrennt.
- Vorhandene LaunchAgents können nach GUI-Ende weiterlaufen. Eine dann weiter aktive zentrale Überwachung wird ohne Agenten nicht versprochen. Ein separater Hintergrund-Agent bleibt optional und benötigt eine konkrete ADR-Entscheidung, falls sein Umfang den bestehenden Architekturvertrag ändert.
- Private Runner-Schlüssel werden gemäß docs/08 nicht kopiert. Migration muss Registrierung und gegebenenfalls serverseitige Kompensation ausdrücklich berücksichtigen.

## Vorläufige v0.5-Abnahmematrix

Diese Zuordnung ist ein Ausgangspunkt für den Abschlussplan, noch keine Freigabe zur Veröffentlichung. „Abgedeckt“ bezeichnet die genannten Szenarien, keine vollständige Zeilenabdeckung.

| Bereich | Beleg / Testdateien unter `Packages/OctoRunnerKit/Tests/OctoRunnerKitTests` | Verbleibende Prüfung oder Anpassung |
|---|---|---|
| Settings-Persistenz und sichere Defaults | `AppPreferencesTests.swift` | Wirkung je Einstellung bestätigen; globale Parallelität erst v0.6 |
| Login/Dock/Sprache ohne Start-Prompts | `AppIntegrationTests.swift`, `SettingsTests.swift` | Reale SMAppService-Zustände mit OS-Freigabe sind zusätzlich interaktiv |
| Update-/Versionsinformationen in Settings | Noch gezielt gegen docs/07 abzugleichen; vorhandene `AppUpdatePrereleaseTests.swift` decken nicht automatisch die Settings-Oberfläche ab | Offener Abnahmepunkt; zurückgestellte Debug-Versionsanzeige nicht ungefragt mitändern |
| Shell/PATH/Restart neuer LaunchAgents | `RunnerLaunchConfigurationTests.swift` | Gilt ausdrücklich für neue Dienste, kein behauptetes Live-Umschreiben bestehender Runner |
| Native Mitteilungen und Ereignisfilter | `AppNotificationTests.swift`, `LocalJobFailureMonitorTests.swift` | Reale Banner mit Opt-in prüfen; Crash-Trigger folgt v0.6 |
| Cache/Retention/Pruning | `WorkspaceCleanerTests.swift`, `StorageMaintenanceTests.swift` | Keine pauschale Bereinigung globaler Host-Caches; sichere verwaltete Pfade gemäß docs/15 |
| Jobs, Queue, Kennzahlen und Kontotrennung | `WorkflowHistoryLoadingTests.swift`, `WorkflowHistoryMetricsTests.swift` | Geladenes Fenster und Beobachtungsalter sichtbar; Logs per bewusstem GitHub-Link, lokale Live-Logs folgen Engine-Plan |
| Audit-Filter, Runner-Auswahl, Export | `AuditLogDialogTests.swift`, `RunnerFilterRegressionTests.swift` | Engine-Start/Stop/Crash-Ereignisse folgen ihren echten Funktionen in v0.6 |
| Telemetrie und API-Budget | `HostTelemetryDashboardTests.swift`, `HostDiskIOMonitorTests.swift`, `TelemetryKitTests.swift` | Reale Werte und „nicht verfügbar“, kein erfundener Ping/IPC-Watchdog |
| Prozessdetails und bestätigtes SIGTERM | `RunnerProcessInspectorTests.swift`, `RunnerProcessInspectorUITests.swift` | Identität erneut prüfen; verbleibendes POSIX-Rennen ist dokumentiert |
| Filter-Empty-States / Resize | `RunnerFilterRegressionTests.swift`, `ResponsiveLayoutTests.swift`, NSHostingView-Tests | Nutzer hat Settings-Lesbarkeit und Resize bereits positiv abgenommen; spätere Änderungen erneut prüfen |
| Abbruch während API-/View-Arbeit | `WorkflowHistoryLoadingTests.swift` und Prozess-/Storage-Tests | Kontowechsel/verspätete Antworten sind explizit abgesichert; Lücken im Abschluss gezielt ergänzen |

Versionsanzeige des Entwicklungsbuilds nicht nebenbei ändern: Der Nutzer hat diesen Fix ausdrücklich zurückgestellt. Die Release-Versionierung bleibt davon getrennt.

## Testabdeckung: bekannte Lücken

Der lokal geprüfte SPM-LLVM-Bericht enthält **13.239 von 16.985 instrumentierten Quellzeilen (77,9 %)**. Das ist keine Gesamtbewertung der App: separate native UI-Läufe und Betriebssystemdialoge sind darin nicht vollständig enthalten. Eine reine Prozentgrenze ersetzt keine Verhaltenstests.

Besonders relevant für die folgenden Pläne:

- `RunnerProvisionerActor.swift`: 30,7 %; Fehlerstufen und Kompensationen müssen im Migrationsplan gezielt abgesichert werden.
- `GitHubRunnerProvisioningAPI.swift`: 5,0 %; echte Transport-/Decoding-/Berechtigungsfälle mit Stub-Transport im v0.6-Registrierungs- und Sync-Umfang ergänzen.
- `GitHubRunnerSyncActor.swift`: 8,5 %; typisierte Fehler, Abbruch, Pagination und Kontoisolation sind ausdrückliche Aufgaben des Sync-Plans.
- `AppUpdaterActor.swift`: 24,8 %; Fehler-/Rollbackpfade sind ausdrückliche Aufgaben des v0.7-Plans.
- Einige SwiftUI-Wrapper haben im SPM-Bericht 0 %, obwohl darunterliegende Inhalte separat gerendert werden. Für die tatsächliche Navigation und Task-Verkabelung müssen die nativen UI-Tests sowie gezielte Lifecycle-Tests hinzukommen; „0 %“ weder als vollständige Funktionslücke noch als erledigte Abdeckung behandeln.
- Vorhandene triviale Assertions wie `isEnabled == true || isEnabled == false` prüfen kein Verhalten. Im v0.5-Abschluss entfernen oder durch nachweisbare Zustands-/Fehlerprüfungen ersetzen, vorhandene aussagekräftige Login-Tests dabei weiterverwenden.

## Nachverfolgung aus dem CI-Review

Separater kleiner Folgepunkt vor dem v0.5-Release: Wenn ein Testprozess stdout schließt, aber weiterläuft, kann der Watchdog bis zur Frist unnötig CPU verbrauchen. Eigener Regressionstest für EOF ohne Prozessende, danach Selector abmelden und begrenzt warten. Dies ist von der noch nicht abschließend zugeordneten Ursache des ursprünglichen CI-Stillstands getrennt.

## Gemeinsame Abnahme und Versionsregeln

Für jeden Codeabschnitt: rote Tests, minimale Umsetzung, grün, Review, PR-CI, Merge, main-CI. Für jeden Release zusätzlich Signierung, Notarisierung, Stapeln, GitHub Release, Tap und lokale Brew-/Gatekeeper-Prüfung. Xcode-Start und signiertes ZIP bleiben als Abnahme ohne Homebrew verfügbar, siehe [Entwicklungsabnahme](./10-development-and-acceptance.md).

Screens in `docs/assets/screens` dienen pro Dialog erneut als Funktionsreferenz. Bestehende lesbarere native Navigation bleibt erhalten; keine starre Pixelkopie. Manuelle Abnahmen werden auf höchstens drei zusammengehörige Punkte gebündelt.

**Nach v0.7.0 stoppen und den Nutzer nach v1.0.0 fragen. Ohne ausdrückliche Freigabe kein v1.0.0.**
