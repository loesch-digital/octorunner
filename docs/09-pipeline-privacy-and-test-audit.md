# Pipeline-, Datenschutz- und Testprüfung (2026-11-11)

## Geprüfter Release-Stand

- [v0.4.2](https://github.com/loesch-digital/octorunner/actions/runs/43046560949) scheiterte an der Signing-Keychain. Match importierte das Zertifikat, anschließend meldete der Signing-Schritt `The specified item could not be found in the keychain`.
- [v0.4.3 Release](https://github.com/loesch-digital/octorunner/actions/runs/43049252599) und [main-CI](https://github.com/loesch-digital/octorunner/actions/runs/43049252861) sind grün. Der Keychain-Suchpfad-Fix ist bereits ausgeliefert. Ein erneutes v0.4.3-Tag oder Ersetzen des Archivs ist ausgeschlossen.

## Patch v0.4.4

Die CI lief bislang mit dem Standard-Xcode des `macos-15`-Images. Die zusätzliche Prüfung auf dem offiziellen `xcode-27`-Image wählt Xcode 27.2 explizit; macOS 15 bleibt ein eigener Kompatibilitätslauf. Der Release verwendet Xcode 27.2. Das Deployment Target bleibt macOS 15. Swift-Sprachmodus 6 und `complete` Strict Concurrency sind weiterhin verbindlich; eine minimale SPM-Tools-Version 6.0 bezeichnet keinen veralteten Compiler.

Verifiziert am 2026-11-11: lokal Xcode 27.2 (27B52), Swift 6.4.2; aktuelle stabile Xcode-Version 27.2, checkout v7.0.1, release-it 21.1.2. Referenzen: [Apple](https://developer.apple.com/xcode/system-requirements/), [Runner-Images](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md), [checkout](https://github.com/actions/checkout/releases).

Homebrew-Verfügbarkeitsprüfungen sind stumm; Installationsfehler bleiben sichtbar. Python-Signingtests laufen auch vor Releases. CI erhält nur `contents: read`. Release-Publikationen werden serialisiert und `gh release create --verify-tag` verweigert vorhandene Releases, statt Archive mit `--clobber` auszutauschen. PR-CI läuft weiterhin ausschließlich auf `pull_request`; nur main hat zusätzlich Push-CI.

Die CI erzeugt Coverage pro Betriebssystem und bewahrt die JSON-Berichte 14 Tage als Artefakte auf (`actions/upload-artifact@v7`, aktuelle Version v7.0.2 geprüft). Es gibt bewusst noch keine pauschale Prozent-Hürde: Aussagekräftige Fehlerpfadtests gehen vor einer durch UI-Rendering erhöhten Gesamtzahl.

## Warum macOS nach Dokumente-Zugriff fragte

Der Starttask suchte automatisch nach `.runner` unter `~/Documents/apps/actions-runner` und `~/Documents/actions-runner`, außerdem unter Pfaden aus der Prozessliste. Die eingebettete Logansicht las auch bereits importierte externe Runner beim Start. Dies sind Zugriffe der installierten App; der Speicherort des OctoRunner-Quellrepos ist nicht die Ursache. [Apple: Ordnerzugriff](https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac).

Nach Abstimmung mit dem Nutzer:

- Automatisch: `~/actions-runner`, `~/.octorunner/runners/*` und `~/Library/Application Support/io.octorunner.macos/runners/*`.
- Externe Runner: zuerst bewusst über **Import Folder…** auswählen. Prozessmetadaten allein sind keine Ordnerfreigabe.
- Externe eingebettete Logs: zuerst **Refresh** oder **Full Console** wählen. Externe Pfade werden vor jeder Dateisystemauflösung von der automatischen Policy abgewiesen.
- Automatische Suche folgt keinen Symlinks aus diesen Bereichen heraus. Diagnostik liest weder verlinkte `_diag`-Ordner noch verlinkte Logdateien.

Die macOS-Freigabe wird nicht umgangen oder pauschal beantragt. Erst die konkrete Nutzeraktion kann einen notwendigen Systemdialog auslösen. Bereits erteilte Systemfreigaben bleiben unverändert.

## Minimale GitHub-Rechte

Der OAuth-Scope `workflow` ist für Runner-Verwaltung und Job-Historie unnötig: Er erlaubt das Ändern von Workflow-Dateien. Er wird nicht mehr angefordert. Bestehende Freigaben werden dadurch nicht automatisch entzogen; für weniger Rechte ist eine neue Autorisierung nötig.

| Verwendung | OAuth / classic PAT | Fine-grained PAT |
| --- | --- | --- |
| Private Repository-Runner registrieren / Labels ändern | `repo`, Administrator des Zielrepos | Nur ausgewählte Repos, Administration: write |
| Organisations-Runner registrieren / Labels ändern | `admin:org`, ggf. zusätzlich `repo` für private Repos | Self-hosted runners: write für die Zielorganisation |
| Künftige Workflow-/Job-Historie lesen | `repo` für private Repos, kein `workflow` | Actions: read für die Zielrepos |

Der aktuelle OAuth-Flow unterstützt beide Runner-Arten und fordert deshalb weiterhin `repo` und `admin:org` an. Ein nur für ausgewählte Repos ausgestellter Fine-grained PAT ist die engere Alternative. Ein eigener OAuth-Schritt für optionale Organisationsrechte kann im Settings-Meilenstein ergänzt werden. Fehlende `X-OAuth-Scopes` bei Fine-grained PATs bedeuten unbekannte Rechte; die App erfindet dafür keine Standardrechte mehr. Die Ziel-API prüft die tatsächlichen Rechte bei Verwendung.

Quellen: [Runner-Endpunkte](https://docs.github.com/en/rest/actions/self-hosted-runners), [OAuth-Scopes](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps), [Fine-grained permissions](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens).

## Testabdeckung und Grenzen

Ausgangsbasis: 29 Swift-Tests, 6 Python-Tests. Der Patch ergänzt ausführbare Workflow-Regressionen, HTTP-Request-/Auth-Fixtures, Ordner-/Symlink-Grenzen sowie den Quit-Dialog. NSHostingView-Rendering und Kontrasttests bleiben erhalten. Renderabdeckung beweist weder vollständige Interaktionen noch VoiceOver-Konformität.

Coverage-Messung mit `swift test --package-path Packages/OctoRunnerKit --no-parallel --enable-code-coverage`, Zwischenstand vor den abschließenden Log-Symlink-Tests:

| Modul | Ausgeführte Zeilen |
| --- | ---: |
| AppShellFeature | 68,0 % |
| CoreModels | 72,3 % |
| DesignSystem | 100,0 % |
| GitHubAPI | 27,0 % |
| RunnerEngine | 25,1 % |
| SecurityKit | 89,2 % |
| SyncKit | 61,7 % |
| TelemetryKit | 97,1 % |

Diese Zahlen sind keine Freigabe als „vollständig abgedeckt“: SwiftUI-Generics erhöhen die Zahl der instrumentierten Zeilen. Besonders OAuth-Polling/Cancellation, Fehlerantworten/Paginierung, Provisioning-Rollback, Crash-Supervision und echter Update-Rollback brauchen weitere Verhaltenstests in v0.5–v0.7. Die bisherige Telemetrie-Testabdeckung belegt ebenfalls keine vollständige Hardware-Telemetrie; die Implementierung enthält noch einen geschätzten Speicherverbrauch.

Manuelle Nutzerabnahme abgeschlossen: fünfmal **Dashboard** im Menüleistenfenster öffnet weiterhin genau ein Fenster; Schließen und Wiederöffnen funktionieren; Quit-Dialog und Beenden funktionieren; erneuter normaler Start ohne Dokumente-Abfrage; die drei Vorschau-Schalter sind deaktiviert. Separat noch nicht live belegt sind das Weiterlaufen konkreter LaunchAgent-Runner und ein neuer externer Ordnerimport. Die Computersteuerung meldet `cgWindowNotFound`; die genannten UI-Ergebnisse stammen ausdrücklich vom Nutzer. Kein TCC-Reset und keine Änderung von Datenschutzfreigaben für Tests.

## Weitere Meilensteine

v0.5.0: sechs Settings-Tabs mit tatsächlicher Wirkung, Jobs/Queue, echte Host-Telemetrie und Audit-UI. v0.6.0: vollständiger Supervisor, sichere Importmigration, periodische Synchronisierung und sichtbare Konflikte. v0.7.0: DE/EN, Accessibility, echte Update-/Rollback-Prüfung, Dokumentation und Screenshots. Diese Meilensteine sind durch diesen Patch nicht erledigt. Nach v0.7.0 ohne ausdrückliche Freigabe kein v1.0.0.
