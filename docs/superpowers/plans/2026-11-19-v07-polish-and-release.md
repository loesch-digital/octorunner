# v0.7 Politur und letzte geplante Version Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Native Umsetzung; bestehende Nutzerfreigabe zur anschließenden Implementierung beachten.

**Goal:** Alle gelieferten Dialoge zugänglich, konsistent lokalisiert und gegen reale Updates geprüft als v0.7.0 liefern.

**Architecture:** Bestehende Funktionen werden systematisch abgenommen. Update-Installation bekommt überprüfbare Fehler-/Rollbackzustände; neue Funktionen werden nur aufgenommen, wenn sie zum ausdrücklich freigegebenen Umfang gehören.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, SPM, macOS ServiceManagement; bestehende Python-/GitHub-Actions-Werkzeuge.

**Spec:** `docs/02-design-system-and-hig.md`, Screens 01–09, `docs/10-development-and-acceptance.md`, `docs/release-signing.md`, Nutzerumfang v0.7; verbindliche Umfangsentscheidung vom 19.11.2026: globales Parallelitätslimit erst v0.6.

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

1. Lange deutsche Texte und viele Runner dürfen Controls nicht unzugänglich machen (Task 1).
2. VoiceOver und Tastatur dürfen keine reine Farb-/Hover-Funktion vorfinden (Task 1).
3. Fehlende Rechte/Netzwerk/Runner dürfen nicht wie Erfolg oder leere Erstinstallation aussehen (Task 2).
4. Beschädigtes Update darf funktionsfähige Installation nicht ersetzen (Task 2).
5. Erststart nach Update mit altem Store muss funktionieren oder kontrolliert zurückfallen (Task 2).

### Task 1: Lokalisierung, Layout und Accessibility

**Files:** `AppShellFeature/Resources/Localizable.xcstrings`, betroffene Views/OctoTheme; bestehende `ResponsiveLayoutTests.swift`, `AppShellUITests.swift`, `RunnerStatusColorTests.swift` und zusätzliche gezielte Accessibility-Tests im bestehenden Testtarget.

**Interfaces:** Gemeinsame Statusbezeichnungen: Verfügbarkeit getrennt von letztem Jobresultat; Running blau in App und Menü, kein erneutes SwiftUI-MenuBar-Invalidierungsproblem.

- [ ] Screens 01–09 pro Dialog abgleichen, Funktionen statt Pixelkopie dokumentieren. String-Katalog auf fehlende DE/EN-Texte und Plural-/Formatfehler prüfen.
- [ ] Für jede gefundene Lücke zuerst roten Test: lange Namen/Labels, viele Wizard-Runner, schmale/breite Fenster, Settings-Suche, leer/Fehler/geladen; dann gezielt korrigieren.
- [ ] VoiceOver-Lesereihenfolge, Fokus, Tastaturaktionen und Kontrast in Hell/Dunkel prüfen. Status nie allein über Farbe vermitteln. NSHostingView ergänzt die manuelle VoiceOver-Abnahme.
- [ ] Tests/Build grün, Review, Commit und beide CI-Gates.

### Task 2: Fehlerbehandlung und echter Update-Rückfall

**Files:** `GitHubAPI/AppUpdaterActor.swift`, zugehörige UI/Update-Installation, `OctoRunnerPersistence.swift`; bestehende `AppUpdatePrereleaseTests.swift` und neue `AppUpdateRecoveryTests.swift` im Testtarget.

**Interfaces:** Zustände prüfen/downloaden/validieren/installieren/neu starten/fehlgeschlagen/wiederherstellen; letzte funktionierende Installation erst nach validierter Ersatzinstallation freigeben. Keine Secrets oder vorsorglichen Ordnerzugriffe.

- [ ] Rote Tests für kaputtes Archiv, fehlende Schreibrechte, falsche App-Identität, abgebrochenen Austausch, Startfehler und bestehenden SQLite-Store; keine Rückmigration eines produktiven Stores behaupten.
- [ ] Sichere Staging-/Validierungs-/Rollback-Schritte ergänzen; Version/Signatur/Gatekeeper, atomarer Dateiaustausch soweit möglich und Wiederanlaufzustand nach Prozessende prüfen.
- [ ] Mit einem echten signierten vorhandenen Release in separater Testinstallation Updatestart und Rückfall prüfen. Produktive App und Runner nicht als zerstörbare Fixtures verwenden. Falls ein irreversibles Schema-Upgrade vorliegt, Backup-/Recovery-Vertrag vor Anwendung explizit festlegen.
- [ ] Grün, Review, Commit und beide CI-Gates.

### Task 3: Dokumentation und v0.7.0

**Files:** `README.md`, `docs/README.md`, `docs/18-remaining-delivery-plan.md`, `docs/assets/screens/`, `docs/releases/v0.7.0.md`.

**Interfaces:** Konsumiert verifizierte v0.6 und Task 1/2; liefert aktuelle Nutzerdoku und unveränderliches signiertes Release.

- [ ] Öffentliche `README.md` ausschließlich auf Englisch erstellen (Nutzerentscheidung 19.11.2026). Aufbau und Verständlichkeit an https://github.com/podman-desktop/podman-desktop orientieren: Produktname/kurzer Nutzen, reales App-Screenshot als Einstieg, übersichtliche Navigation und Features mit passenden Screenshots. Keine Funktionen als fertig ausweisen, die noch geplant sind.
- [ ] Installation mit geprüften Copy-and-paste-Befehlen für Homebrew (Tap/Cask) und alternativ signiertem Release-ZIP beschreiben; Voraussetzungen macOS/Architektur, Updates und erster Start erklären. Keine Gatekeeper-Umgehungen empfehlen.
- [ ] Quick Start: GitHub verbinden, minimale Rechte je Funktion, Runner hinzufügen/importieren, Workflow-Labels `runs-on` konfigurieren und Status/Jobs ansehen. GUI-/LaunchAgent-Lebensdauer sowie Grenzen von Neustart und Parallelität klar benennen.
- [ ] Entwicklungsabnahme ohne Homebrew über Xcode und vorhandene lokale Startskripte dokumentieren, einschließlich Voraussetzungen und tatsächlich geprüfter Build-/Testbefehle. Auf ausführliche Entwickler-/Architekturdoku verlinken statt deren Inhalt in die README zu kopieren.
- [ ] Aktuelle echte App-Screenshots für Dashboard, Runner-Assistent, Details/Logs, Jobs/Workflow und Einstellungen aufnehmen, ohne Tokens/private Daten; Mockups in `docs/assets/screens/` nur als Designvorlage verwenden. Bilder mit englischen Alt-Texten, funktionierenden relativen Links und angemessener Größe einbinden.
- [ ] Verifizierte CI-/Release-Badges, Release-/Support-/Lizenzlinks ergänzen, soweit tatsächlich vorhanden. README nur einmal auf Englisch, keine parallelen Übersetzungen. Alle Links, Homebrew-/ZIP-Schritte und Bilddateien vor Release prüfen.
- [ ] `docs/README.md`, Lieferplan und Release Notes auf tatsächlichen Funktionsstand bringen.
- [ ] Vollständige Tests, nativer Build, grüne PR-/main-CI. `npx release-it 0.7.0 --ci`, danach Release-Lauf, Homebrew-Installation, App-Start und Gatekeeper vollständig prüfen.
- [ ] Deutsche Abschlussübersicht mit offenen Einschränkungen und höchstens drei manuellen Punkten liefern.
- [ ] **STOPP nach v0.7.0:** Nutzer ausdrücklich fragen, ob und wann v1.0.0 erscheinen soll. Kein v1.0.0-Tag und keine automatische Fortsetzung.
