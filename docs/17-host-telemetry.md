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
