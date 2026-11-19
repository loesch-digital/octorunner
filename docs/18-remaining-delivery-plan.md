# Restliche Umsetzung bis v0.7

Stand: 19. November 2026. Dies ist der aktuelle Arbeitsindex; ältere Detailpläne dokumentieren teilweise frühere Zwischenstände und bleiben als Historie erhalten.

## Verbindlicher Umfang

Der Nutzer hat am 19.11.2026 entschieden: **Das globale Runner-Parallelitätslimit wird nach v0.6 verschoben.** Es blockiert v0.5 nicht mehr. Ein gespeicherter Wert ist bis zur Engine-Integration keine wirksame Begrenzung und darf nicht als solche dargestellt werden.

| Reihenfolge | Liefergegenstand | Plan / Abhängigkeit |
|---|---|---|
| 0 | Nachgewiesene Hänger beheben, Diagnose sichern | [CI-Testdiagnose](./superpowers/plans/2026-11-14-ci-test-diagnostics.md); PR #27–29 gemergt, aktuelle main-CI grün |
| 1 | v0.5 abnehmen, GitHub-Details ergänzen und signiert veröffentlichen | [v0.5 Abschluss](./superpowers/plans/2026-11-19-v05-acceptance-and-release.md) |
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

## Ergänzter Jobs-Umfang vom 19.11.2026

Der Nutzer hat die sichtbare PR-Verknüpfung und eine Actions-ähnliche Workflow-/Job-Detailansicht ausdrücklich nachgefragt. Der aktuelle Code zeigt Trigger, Branch/Commit, Run-Status, Jobliste und einen Run-Weblink, aber **keine PR-Nummer/-Verknüpfung, keine Step-Liste und keine in der App geladenen GitHub-Job-Logs**. Dies ist kein bereits vollständig umgesetzter Bereich. Der [separate Umsetzungsplan](./superpowers/plans/2026-11-19-workflow-github-details.md) ist zusätzliche Abhängigkeit vor dem stabilen v0.5-Release. Laufende Step-Zustände und verfügbare Log-Dateien werden getrennt; lokale Live-Logs bleiben im v0.6-Engine-Plan.

## Begründete Grenzen statt Platzhalterfunktionen

- Crash-/Quarantäne-Mitteilungen werden erst mit echter Prozessaufsicht aktiviert. Keine scheinbar wirksamen Laufzeitschalter.
- Jobs-Metriken beziehen sich auf tatsächlich geladene Historie; keine erfundene vollständige GitHub-SLA.
- Telemetrie zeigt echte verfügbare Messwerte; keine geschätzte P-/E-Core-Auslastung oder unbelegte Prozesszuordnung.
- Personal Multi-Repo bedeutet mehrere Repository-Registrierungen. Prefix benennt Runner, Labels steuern Routing, Organisationsgruppen steuern Zugriff; diese Konzepte bleiben getrennt.
- Vorhandene LaunchAgents können nach GUI-Ende weiterlaufen. Eine dann weiter aktive zentrale Überwachung wird ohne Agenten nicht versprochen. Ein separater Hintergrund-Agent bleibt optional und benötigt eine konkrete ADR-Entscheidung, falls sein Umfang den bestehenden Architekturvertrag ändert.
- Private Runner-Schlüssel werden gemäß docs/08 nicht kopiert. Migration muss Registrierung und gegebenenfalls serverseitige Kompensation ausdrücklich berücksichtigen.

## v0.5-Abnahmematrix vor PR-Freigabe

Diese Zuordnung dokumentiert die lokale Prüfung; PR-/main-CI und Release-Prüfung sind weiterhin eigene Freigabestufen. „Abgedeckt“ bezeichnet die genannten Szenarien, keine vollständige Zeilenabdeckung.

| Bereich | Beleg / Testdateien unter `Packages/OctoRunnerKit/Tests/OctoRunnerKitTests` | Verbleibende Prüfung oder Anpassung |
|---|---|---|
| Settings-Persistenz und sichere Defaults | `AppPreferencesTests.swift` | Wirkung je Einstellung bestätigen; globale Parallelität erst v0.6 |
| Login/Dock/Sprache ohne Start-Prompts | `AppIntegrationTests.swift`, `SettingsTests.swift` | Reale SMAppService-Zustände mit OS-Freigabe sind zusätzlich interaktiv |
| Update-/Versionsinformationen in Settings | `SettingsUpdateTests.swift`: manuelle Auslösung, Fehler, Abbruch, Doppelaufrufe, DE/EN-Suche und Rendering mit 100 Runnern | Vorhandenen Release-Checker wiederverwendet; keine automatische Abfrage beim Öffnen, kein Ordnerscan. Debug-Versionsanzeige bleibt unverändert. Native Navigation wird separat in CI geprüft. |
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
- Die triviale Assertion `isEnabled == true || isEnabled == false` wurde entfernt. `AppIntegrationTests` prüft stattdessen bereits tatsächliche Login-Registrierung, Fehler, ausstehende OS-Freigabe und veraltete Statusantworten.

## Nachverfolgung aus dem CI-Review

Erledigt in Commit `d39cb3b`: Der Watchdog meldet geschlossenes stdout vom Selector ab. Der rote Profiling-Test zählte zuvor 370.433 Schleifendurchläufe in 0,8 Sekunden. Regressionen prüfen begrenztes Warten, erhaltenen Exitcode und weiter wirksame Idle-/Gesamtfristen. Dies ist ein zusätzlicher Performance-Fix, keine nachträgliche Behauptung über die ursprüngliche CI-Hängerursache.

## Gemeinsame Abnahme und Versionsregeln

Für jeden Codeabschnitt: rote Tests, minimale Umsetzung, grün, Review, PR-CI, Merge, main-CI. Für jeden Release zusätzlich Signierung, Notarisierung, Stapeln, GitHub Release, Tap und lokale Brew-/Gatekeeper-Prüfung. Xcode-Start und signiertes ZIP bleiben als Abnahme ohne Homebrew verfügbar, siehe [Entwicklungsabnahme](./10-development-and-acceptance.md).

Screens in `docs/assets/screens` dienen pro Dialog erneut als Funktionsreferenz. Bestehende lesbarere native Navigation bleibt erhalten; keine starre Pixelkopie. Manuelle Abnahmen werden auf höchstens drei zusammengehörige Punkte gebündelt.

**Nach v0.7.0 stoppen und den Nutzer nach v1.0.0 fragen. Ohne ausdrückliche Freigabe kein v1.0.0.**

## Funktionsabgleich mit Screens 07–09

Die nativen, vom Nutzer positiv abgenommenen Settings-Seiten bleiben erhalten. Die Screens sind Funktionsreferenzen, keine Vorgabe für starre Größen oder veraltete Systemintegration.

| Referenz / Umfang | Ergebnis und Beleg |
|---|---|
| 07 General: Erscheinungsbild, Sprache, Versionen/Updates | Vorhanden in `GeneralSettingsTab`/`SettingsUpdateCard`; Preferences-, Integrations- und neue Update-Tests. Betriebssystemabhängige Login-Freigaben bleiben interaktiv. |
| 07 Autostart/Background und 07d Failover | Begründet angepasst: `SMAppService.mainApp`, Shell/PATH und KeepAlive für neue LaunchAgents. Bestehende Dienste werden nicht still umgeschrieben. Echte Prozessaufsicht, Quarantäne und globales Parallelitätslimit folgen v0.6. |
| 07c Auth sowie ergänzende Cache-/Storage-Seite | Vorhanden gemäß docs/15 und docs/13: überprüfte verwaltete Verzeichnisse, Vorschau/Bestätigung, Aufbewahrung; Keychain und reale Rechte-Metadaten. Kein pauschales Löschen globaler Host-Caches, keine erfundene Token-Laufzeit oder funktionslose Touch-ID-Option. |
| 07e Mitteilungen | Native macOS-Mitteilungen mit Opt-in und Ereignisfiltern; Banner/Ton über Systemeinstellungen. Crash-Ereignisse bleiben bis zur Engine deaktiviert. `AppNotificationTests` und Ereignismonitor-Tests. |
| 08 Jobs und Queue | Vorhanden gemäß docs/12: Kontotrennung, Filter, persistierte Historie, aktuelle Queue und Kennzahlen des geladenen Zeitfensters. Logs über bewusste GitHub-Links; keine behauptete vollständige SLA. Lokales Streaming folgt v0.6. |
| 09 Host-Telemetrie | Vorhanden gemäß docs/17: echte CPU-/RAM-/I/O-/API-Messwerte, Speicherdruck und thermischer Zustand. P-/E-Core-Anzahl statt unbelegter separater Auslastung; Host-I/O statt erfundener APFS-Volume-Zuordnung. |
| 09 Prozessinspektor und ergänzende Audit-Funktionen | Prozessinspektor mit Identitätsprüfung, CPU/RAM/Laufzeit und bestätigtem SIGTERM; Audit-Filter, Runner-Auswahl und Export gemäß docs/16. Vollständige Engine-Start/Stop/Crash-Ereignisse und echte lokale Live-Logs folgen v0.6. |

### Explizite Abweichungen vom ursprünglichen Settings-Mockup

- **Service-PID/Laufzeit, Reload, Plist-Vorschau und Syntaxprüfung (07):** noch offen für die LaunchAgent-Betriebsansicht; ausdrücklich im v0.6-Engine-Plan Task 1 erfasst. Die bereits vorhandene Prozesslaufzeit im Telemetrie-Inspektor ersetzt diese Dienstdiagnose nicht.
- **Organisations-/Workpool-Berechtigungstabelle und manueller Permission-Sync (07c):** noch nicht vorhanden. Die aktuelle Auth-Seite zeigt reale Account-/Scope-Metadaten, keine vollständige Organisationsfreigabe. Dies wird mit Gruppen und explizitem Abgleich im v0.6-Sync-Plan Task 3 umgesetzt; fehlende Berechtigung bleibt ein sichtbarer Fehler.
- **Graceful Drain und Timeout (07d):** noch offen, v0.6-Engine-Plan Task 1/3. Die aktuellen Restart-Voreinstellungen sind keine Drain-Funktion.
- **Standby-Host (07d, Phase 2 Preview):** bewusst nicht als wirkungsloser Schalter aufgenommen. Automatischer Host-Failover ist zusätzlicher Phase-2-Umfang außerhalb der bestätigten v0.5–v0.7-Lieferung und benötigt ein gesondertes Konzept/Freigabe; kein Ersatz durch lokales Auto-Restart.

### Die fünf Review-Fälle

1. Wirksame Einstellungen: `AppIntegrationTests.loginFailure/loginApproval/loginSuccess/dockStartupActivation`, `RunnerLaunchConfigurationTests`, Storage- und Notification-Tests belegen die dokumentierte Wirkung; Engine-abhängige Schalter behaupten keine Wirkung.
2. Kontowechsel: `WorkflowHistoryLoadingTests.accountSwitch/invalidatedResponse/globalRefreshCancellation` verwerfen verspätete Antworten vor Persistenz.
3. Leere Filter: `RunnerFilterRegressionTests.emptyStates/runnerChoices` unterscheiden fehlende Registrierung, Filtertreffer und Suchtreffer einschließlich historischer Runner.
4. Fensterabbau: `RunnerProcessInspectorTests.cancellation`, History-Abbruchtests und `SettingsUpdateTests.cancelledCheck` verhindern späte Ergebnisse/Modellzugriffe. Die periodische Telemetrie prüft Cancellation nach jedem Await.
5. Release-/Updatefehler: `SettingsUpdateTests.failedCheck/cancellationError` unterscheiden Fehler von erfolgreicher Prüfung. Installations-Rollback gehört zum v0.7-Plan; Brew/Gatekeeper und signierter Release sind noch ausstehende Release-Gates.

### Aktuelle lokale Verifikation

Am 19.11.2026 bestanden **293 Swift-Tests in 62 Suites**, einschließlich neuer Settings-Tests und aller bisherigen Regressionen. Zusätzlich bestanden alle **33 Python-Tests** mit dem für Prozessdiagnose und Compiler-Caches erforderlichen Zugriff; ein zuvor eingeschränkter Sandbox-Lauf wird nicht als Produktfehler oder erfolgreicher Test gezählt. Der native Debug-App-Build mit Xcode war erfolgreich. Die neuen Settings-Karten wurden in DE/EN, Hell/Dunkel und bei 620/960 Punkten gerendert und visuell geprüft. Native XCTest-Interaktion kann lokal wegen fehlender macOS-Automatisierungsinitialisierung nicht ausgeführt werden; sie wird ausdrücklich nicht als bestanden gezählt und muss in PR-/main-CI grün sein. Frühere positive Nutzerabnahmen für Settings-Lesbarkeit, Resize, Single-Window und Start ohne Dokumente-Abfrage bleiben erhalten.

## GitHub-Details: ergänzendes v0.5-Gate

PR #30 und main-CI [44511598034](https://github.com/loesch-digital/octorunner/actions/runs/44511598034)
sind vollständig grün. Der anschließende Feature-Zweig ergänzt validierte PR-Links,
Jobs/Steps je bekanntem Run-Versuch und bewusst geladene Job-Log-Momentaufnahmen.
Screenshot 08 dient als Funktionsvorlage; keine vorgetäuschten Webhooks, REST-Livestreams
oder schreibenden Rerun-/Cancel-Aktionen.

Nach einem unabhängigen Review wurden sechs wichtige Punkte mit Regressionen
korrigiert: vollständige History-Pagination, getrennte GitHub-/Download-Budgets,
explizite Attempt-Prüfung, Aktualisierung wartender Workflows ohne Jobs, gemeinsame
Statusfarben und tatsächlicher Accessibility-Text der nativen Log-Anzeige.
Lokaler Stand: **330 Swift-Tests in 67 Suites**, **33 Python-Tests** und nativer
Xcode-27.2-/Swift-6.4.2-Build grün. Das bestätigt die geprüften Szenarien, keine
pauschale vollständige Testabdeckung. PR-/main-CI und Release sind separate Gates.

Die DE/EN-Log- und Detailansichten wurden schmal/breit sowie Hell/Dunkel gerendert.
Native authentifizierte Detail-/Log-Interaktionen benötigen weiterhin die kurze
Abnahme; die CI prüft die Jobs-Navigation ohne private GitHub-Fixtures.
Bekannte kleine Optimierung: abgeschlossene PR-Läufe können bei weiterhin leeren
GitHub-Metadaten den begrenzten Commit-Lookup erneut ausführen.
