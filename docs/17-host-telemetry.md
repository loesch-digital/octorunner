# Host-Telemetrie

**Host-Telemetrie** in der Seitenleiste zeigt die verfügbaren lokalen Messwerte. Die Ansicht aktualisiert sich bei geöffnetem Bildschirm alle 1, 5 oder 15 Sekunden; **Telemetrie aktualisieren** fordert eine neue Messung an. Beim Verlassen endet die periodische Messung dieser Ansicht.

- **CPU:** Gesamtauslastung aus zwei Mach-Zählerständen sowie erkannte Performance-/Effizienz-Kernanzahlen. Die erste Messung benötigt einen zweiten Zählerstand. Eine Auslastung je Kerntyp wird ohne verifizierbare Zuordnung der CPU-Indizes nicht behauptet.
- **Arbeitsspeicher:** Physischer Gesamtspeicher, belegter Speicher sowie App-, Wired- und komprimierter Speicher aus VM-Statistiken. Das sind hostweite Werte; Dateisystem-Caches sind keine RAM-Kategorie. Ein unbekannter Messwert erscheint als Gedankenstrich.
- **Speicher und I/O:** Verfügbare und gesamte Kapazität des Benutzer-Volumes. Der Read-/Write-Durchsatz stammt aus den verfügbaren `IOBlockStorageDriver`-Statistiken des Hosts und ist ausdrücklich keine Messung eines einzelnen APFS-Volumes. Neue Geräte, fehlende Messungen und Zählerrücksetzungen erzeugen keine künstlichen Spitzen. Die Cache-Größenanalyse bleibt in **Einstellungen → Cache & Speicher**.
- **GitHub-API:** Letzte beim Laden der Jobs beobachtete Rate-Limit-Header des aktiven Kontos einschließlich Messalter und Reset-Zeit. Bei einem Kontowechsel wird nur die Beobachtung dieses Kontos gezeigt. Zum Aktualisieren die Jobs-Ansicht neu laden; diese Telemetrieansicht verbraucht selbst keine zusätzlichen GitHub-API-Abfragen. Alte Antworten überschreiben keine neueren Beobachtungen.

Die Abfragen lesen Systemzähler, Geräte-Metadaten und Volume-Kapazität. Sie durchsuchen weder den Dokumente-Ordner noch Runner-Arbeitsverzeichnisse. Fehlende Messmöglichkeiten werden nicht durch Beispieldaten ersetzt.

Die Karten übernehmen die Hauptbereiche von [Screenshot 09](./assets/screens/09_host_telemetry.png), passen sich aber der Fensterbreite an. Der Prozessinspektor je Runner und die weitere Telemetrie-Vervollständigung folgen als nächste Teilaufgabe; dieser Stand ist noch nicht die vollständige v0.5.0.

## Verifikation

Unit-Tests decken Geräte-Deltas, neue/entfernte Geräte, Zählerrücksetzungen, fehlende Messungen und Zeit-Baselines ab. Weitere Tests prüfen die echte Übernahme der API-Header aus Jobs und die Kontotrennung. NSHostingView-Aufnahmen prüfen fehlende und vorhandene Messwerte bei schmaler/breiter Darstellung in DE/EN und Hell/Dunkel. Ein nativer UI-Test prüft Navigation, Messkarten und die Aktualisierung.

API-Grundlagen: [Apple: IOBlockStorageDriver statistics](https://developer.apple.com/documentation/iokit/ioblockstoragedriver_h_user-space/defines), [Apple: System capabilities](https://developer.apple.com/documentation/kernel/1387446-sysctlbyname/determining_system_capabilities).

## Prozessinspektor je Runner

Unter den Host-Karten zeigt **Prozesse je Runner** eindeutig zugeordnete `Runner.Listener`-/`Runner.Worker`-Prozesse sowie deren erreichbare Kindprozesse desselben macOS-Benutzers. Ein Dropdown filtert nach Runner. PID, Prozessname, Runner, CPU, residenter Speicher und Laufzeit werden im gewählten Messintervall aktualisiert. **Details** öffnet eine lesbare Momentaufnahme einschließlich Startzeit, Eltern-PID, Benutzer-ID, ausführbarer Datei und Messzeitpunkt.

Die CPU-Auslastung entsteht aus zwei kumulativen libproc-Zählerständen und monotoner verstrichener Zeit. Mach-Ticks werden mit `mach_timebase_info` in Sekunden umgerechnet; 100 % entsprechen einem ausgelasteten Kern, deshalb sind Werte über 100 % möglich. Die erste Messung, fehlende Zähler, eine wiederverwendete PID oder ein Zählerreset liefern einen Gedankenstrich. Fehlende bzw. nicht lesbare Prozesse, unvollständige Elternketten, fremde Benutzer und doppelte Runnerpfade werden nicht stillschweigend zugeordnet. Weder Prozessargumente noch Umgebungsvariablen werden gelesen. Es werden keine Runnerordner durchsucht.

**Beenden …** zeigt zuerst eine Bestätigung mit Prozess, PID, Runner und Auswirkung auf aktive Jobs. Danach werden der aktuelle Prozessbaum, PID plus Startzeit, Benutzer, ausführbare Datei und Eltern-PID erneut geprüft. Die Anfrage sendet ausschließlich `SIGTERM` an diesen einzelnen Prozess; sie beendet keine Prozessgruppe und bietet keinen automatischen `SIGKILL`-Rückfall. Die eigene GUI-PID und System-PIDs sind ausgeschlossen. Die POSIX-Schnittstelle ist nicht atomar an eine Prozessidentität gebunden; zwischen letzter Prüfung und Signal bleibt ein kleines Betriebssystem-Rennen möglich.

Ein Audit-Intent wird vor der Anfrage explizit gespeichert. Danach folgt entweder **Process termination signal sent** oder **Process termination refused or failed**. Eine unterbrochene Anfrage kann beim vorbereiteten Eintrag bleiben; dieser bestätigt keinen Signalversand. Auch ein erfolgreiches Signal bestätigt keinen Prozessausgang. Ein LaunchAgent kann den Prozess neu starten. Nach einem Abbruch der Ansicht wird kein SwiftData-Zugriff fortgesetzt.

### Abgleich mit Screenshot 09

Die Hauptfunktionen der Prozessliste sind vorhanden, mit umbruchfähigen nativen Zeilen statt einer breiten, fest dimensionierten Tabelle. Ein `CoreSimulatorService` wird nur dann gezeigt, wenn seine wirkliche Elternkette die Zuordnung belegt; Namensähnlichkeit reicht nicht. Wieder unter `launchd` eingeordnete Dienste lassen sich dadurch gegebenenfalls nicht zuordnen. Einen erfundenen 60-Hz-IPC-Watchdog, simulierte P-/E-Lastwerte oder angebliche RAM-Kategorien für Dateicaches zeigt die App nicht. Prozessmetadaten und Signale verwenden die öffentlichen libproc-/Darwin-Schnittstellen und benötigen keine zusätzlichen GitHub-Rechte.

Noch offen für v0.5: weitere belastbare Hardwarewerte wie Memory Pressure/Thermalzustand sowie die tatsächlich durchgesetzte globale Runner-Concurrency. Die vollständige Prozessaufsicht mit Start/Stop/Restart und Crash-/KeepAlive-Policies bleibt v0.6 vorbehalten.

### Technische Quellen und Prüfung

- [Apple libproc-Schnittstelle](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.h): öffentliche Prozess-Metadatenaufrufe.
- [Apple XNU, fill_taskprocinfo](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c): kumulative User-/System-Zeit aus `recount_times_mach` und residenter Speicher.
- Unit-Tests: eindeutige Zuordnung, fremde/unabhängige Prozesse, doppelte Wurzeln/PIDs, zyklische Elternketten, Startzeitprüfung, CPU-Deltas/Reset, geänderte Identität/Zuordnung vor SIGTERM und Cancellation.
- Native libproc-/SIGTERM-Prüfung ausschließlich mit einem isolierten, im Test erzeugten Prozess; keine bestehenden Runner werden beendet.
- NSHostingView: leere/gefüllte Liste und Detailansicht, 680/1100 Punkte, DE/EN, Hell/Dunkel; zusätzliche native UI-Prüfung für Navigation und Runner-Dropdown in CI.
