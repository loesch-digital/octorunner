# 06 — Step 4: Main Dashboard, Runner Config & Labels, Live Logs & MenuBar (`v0.4.0`)

**Ziel von Step 4 (`v0.4.0`):**  
Vollständige Implementierung der täglichen Arbeits-Dialoge:
- **Dialog 2 (`2._main_dashboard_window`):** Haupt-Dashboard mit Pool-Status, Start/Stop-Steuerung, CPU/RAM-Kurztelemetrie und Live-Worker-Stream.
- **Dialog 4 (`4._advanced_runner_configuration_labels`):** Detail-Konfigurationssheet für einzelne Runner (Custom Labels Tag-Editor, Working Directory & Disk Usage, `launchd` Neustart).
- **Dialog 5 (`5._runner_detail_live_log_view`):** Vollbild-Detailansicht eines Runners mit Step-by-Step Job-Akkordeon, Echtzeit-ANSI-Terminal-Stream (`AsyncStream`) und `Cancel Workflow` / `Open in GitHub`.
- **Dialog 6 (`6._macos_menu_bar_status_item_popover`):** Natives macOS MenuBar-Popover (`MenuBarExtra(.window)`) für schnellen Zugriff aus der Menüleiste.

---

## 1. Dialog 2: Main Dashboard Window (`RunnerDashboardView.swift`)

![Dialog 2: Main Dashboard Window](./assets/screens/02_main_dashboard.png)

### Funktionsumfang & SwiftUI-Umsetzung (`swiftui-pro` & `swiftdata-pro`)
1. **Left Sidebar (`NavigationSplitView` Source List):**
   - Filter-Kategorien mit Live-Badges: `All Runners`, `Active Daemons`, `Failed / Faulted`, `Queue & Workpools`, `launchd Settings`.
   - Nutzt sichere `#Predicate<RunnerEntity>`-Filter und `@Query` direkt in der View.
   - Unten: `+ Register Runner` Button (öffnet Wizard aus Step 3), `Documentation` & `Environment Specs`.
2. **Top KPI Cards (Bento Row):**
   - **Card 1 — Running Instances:** `2 of 2 active` mit globalen Quick-Action-Buttons **`▷ Start All`** und **`□ Stop All`**.
   - **Card 2 — Host CPU Usage:** Live-Prozentanzeige + Kern-Info (`Apple M-Series active`).
   - **Card 3 — Host Memory:** Live Unified Memory Balken (`22.8 / 64 GB — Pressure: Nominal`).
3. **Runner Instance Table:**
   - Zeigt pro Runner: Name + Status-Badge (`IDLE` grün / `BUSY` orange / `OFFLINE` grau / `FAULTED` rot), lokaler Pfad, `launchd PID` (oder aktueller Job-Name wie `CI / iOS Build & Test #42`), Target Scope (`@user` / `owner/repo`), **Label-Chips** (`macos`, `m4-chip`, `ios-build`, `xcode-16`, `fastlane`) und **Row Actions**:
     - `Stop` / `Start` Toggle-Button
     - `⚙️` (öffnet **Dialog 4: Runner Settings Sheet**)
     - `🗑️` (entfernt den Runner lokal via `./config.sh remove` + `launchctl bootout` und über die GitHub API)
4. **Embedded Live Worker Execution Stream (Bottom Panel):**
   - Zeigt für den ausgewählten Runner sofort die letzten Logzeilen aus `~/Library/Application Support/OctoRunner/runners/<name>/_diag/` bzw. `stdout.log` mit `Auto-scroll`, `Clear` und `Export Log`.

---

## 2. Dialog 4: Advanced Runner Configuration & Labels (`RunnerConfigDetailSheet.swift`)

![Dialog 4: Advanced Runner Configuration & Labels](./assets/screens/04_runner_config_labels.png)

Wird über das Zahnrad-Icon (`⚙️`) eines Runners geöffnet:
- **Sub-Navigation Tabs:** `General & Labels`, `Working Directory`, `System (launchd)`, `Advanced Cache`.
- **Runner Metadata & Labels:**
  - Read-only Runner Name & `launchd` Daemon State (`Registered & Idle`).
  - **Interaktiver Label-Tag-Editor (`TagFlowLayout`):** Bestehende Labels können per `×` entfernt und neue Labels über `+ Add Label` hinzugefügt werden.
  - **GitHub API Synchronisation:** Änderungen an den Labels werden direkt über `PUT /repos/{owner}/{repo}/actions/runners/{runner_id}/labels` (bzw. `/orgs/...`) mit GitHub synchronisiert!
- **Workspace & File System:**
  - Zeigt den `_work`-Pfad, einen `Browse...` / `Open in Finder`-Button und die aktuelle APFS-Speicherbelegung (`Disk Space Used: 4.8 GB / 450 GB available`).
- **Footer:** `Reset Defaults`, `Cancel` und **`⚡ Save & Restart Service`**.

---

## 3. Dialog 5: Runner Detail & Live Log View (`RunnerConsoleLogView.swift`)

![Dialog 5: Runner Detail & Live Log View](./assets/screens/05_runner_detail_logs.png)

Wird durch Doppelklick auf einen Runner oder Klick auf **"View Live Log"** geöffnet:
- **Runner Header Card:**
  - Name (`mac-runner-2`), Status-Pill (`Busy`), Laufzeit-Timer (`03m:42s`), CPU/RAM des Runner-Prozesses, verknüpfter Workflow-Run + Branch/Commit-Hash (`(main) @ b93dfa1`).
  - **Aktionen im Logdialog:** „Auf GitHub öffnen“ öffnet den zugeordneten Repository- oder Organisationsbereich. „Diagnoseordner“ öffnet den lokalen Ordner auf Anforderung. Konkrete Workflow-Läufe lassen sich über ihre Laufdetails in „Jobs & Workflow-Läufe“ in GitHub öffnen.
- **Vier Ansichten ab v0.6:**
  - **Live-Ausgabe des Runners** folgt den Prozess-Pipes direkt verwalteter Runner. Bei LaunchAgents folgt sie den Service-Logs, bei extern verwalteten Runnern den lokalen Diagnosedateien.
  - **Hintergrunddienst-Log** folgt `_diag/launchd.stdout.log` und `_diag/launchd.stderr.log`.
  - **Umgebungsvariablen** zeigt die in OctoRunner bekannten Runner-Werte und den konfigurierten Arbeitsordner.
  - **Runner-Diagnose** zeigt die Zusammenfassung und folgt der jeweils neuesten `Runner_*.log`- und `Worker_*.log`-Datei.
- **Live-Anzeige:** Dateisystemereignisse aktualisieren die Ansicht bei Schreibvorgängen und Rotation. Suche, Schweregrad, Pause, Auto-Scroll und Leeren steuern den sichtbaren Ausschnitt. Der Puffer behält bis zu 200 Einträge. Die App weist auf ausgelassene Inhalte hin.
- **Kopieren und Export:** Die Exportaktionen verwenden die gefilterte Ansicht mit maskierten erkannten Zugangsdaten. Beginnt ein Ausschnitt mitten in einer Datei ohne vorherigen Kontext, hält der Export deren Text zurück.
- **Workflow-Steps und Job-Logs:** „Jobs & Workflow-Läufe“ zeigt die von GitHub gemeldeten Steps und lädt die verfügbaren Job-Logs. GitHub dokumentiert einen separaten Download für Job- und Step-Logs. [GitHub REST API](https://docs.github.com/en/rest/actions/workflow-jobs)

---

## 4. Dialog 6: macOS Menu Bar Status Item Popover (`MenuBarPopoverView.swift`)

![Dialog 6: macOS Menu Bar Status Item Popover](./assets/screens/06_menubar_popover.png)

Implementiert als native SwiftUI `MenuBarExtra` mit `.menuBarExtraStyle(.window)`:
- **Header:** Status-Banner `• launchd daemon running (2/2 online)` + Buttons `Open Dashboard (⌘O)` & `Preferences (⌘,)`.
- **Local Workpool Runners Liste:**
  - Kompakte Karten für jeden Runner mit Status (`Idle` / `Busy`), aktuellem Job-Namen, CPU/RAM-Verbrauch und Direkt-Button `Pause / Stop` bzw. `View Live Log (⌘L)`.
- **`launchd` & System Policies Quick-Toggles:**
  - `Autostart at macOS Login` (`SMAppService.mainApp`)
  - `Auto-restart on Crash / Disconnect` (`KeepAlive` in Plist)
  - `Pause All Runners during Battery Saver` (`ProcessInfo.processInfo.isLowPowerModeEnabled`)
- **Footer-Menü:** `Check for App Updates...`, `Actions Runner Engine Version`, `View launchd Daemon Logs`, `Restart Daemon Service (⌘R)` und `Quit (⌘Q)`.

---

## 5. Umfang der ausführbaren Version `v0.4.0` (Was du nach Step 4 testen kannst)

1. Volle Kontrolle über alle Runner im **Main Dashboard** und aus der **macOS Menüleiste** (auch wenn das Hauptfenster geschlossen ist).
2. Live-Beobachtung laufender `xcodebuild`- und `fastlane`-Jobs im **Live Log View** inkl. Workflow-Abbruch und Label-Bearbeitung.
3. Veröffentlichung via `npm run release` als **`v0.4.0`** ins Homebrew Cask.
