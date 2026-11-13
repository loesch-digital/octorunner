# Cache & Storage

Der sechste Einstellungsbereich übernimmt die vorhandene Kartenstruktur. Die
Analyse beginnt per „Speicher analysieren“; der Standard „Nur manuell“ führt
beim App-Start keine Ordneranalyse oder Bereinigung aus. Es werden keine neuen
GitHub-Rechte oder macOS-Mitteilungsrechte benötigt.

## Umfang

Nur direkte Runner-Unterordner unter
`~/Library/Application Support/io.octorunner.macos/runners` werden berücksichtigt.
Als importiert markierte Runner und fremde Pfade sind ausgeschlossen. Nach einer
Migration muss zusätzlich der gespeicherte Dienstname dem kanonischen Namen aus
der Provisionierung entsprechen; veraltete oder abweichende Zuordnungen erlauben
keine Bereinigung. Analysiert werden `_work` und `_diag`:
Workspaces/Tools, Actions-Cache, temporäre Dateien und Diagnoseprotokolle.
Die Größen sind logische Dateigrößen, keine Zusage über physisch frei werdende
APFS-Blöcke. Die verfügbare Kapazität stammt aus den Volumenmetadaten.

Eine Vorschau zeigt die konkreten Kandidaten mit Runner-ID und relativen Pfaden.
Nur alte Workspaces, `_actions`, `_temp` und `Runner_*.log`/`Worker_*.log` sind
bereinigbar. Das neueste Diagnoseprotokoll, `_tool`, andere reservierte Ordner,
Runner-Konfiguration, Binärdateien und launchd-Ausgabeprotokolle bleiben erhalten.
Symlinks werden weder verfolgt noch als Kandidaten angeboten.

## Schutz vor laufenden Jobs

IDLE bedeutet nicht gestoppt. Vor jeder Löschung werden die aktuelle Modellidentität,
fehlende Listener-/Worker-Prozesse und ein tatsächlich entladener LaunchAgent
geprüft. Unbekannte Zustände erlauben keine Löschung. Alter, Dateigrößen und
Dateiidentität werden nach asynchronen Prüfungen erneut gelesen. Veränderungen
seit der Vorschau führen zum Überspringen. Die späteren Start-/Stop-Funktionen
müssen diese Bereinigung mit ihrem Betriebszustand koordinieren.

## Richtlinien

- Manuell: Vorschau und ausdrückliche Bestätigung.
- Automatisch nach Alter: alle zehn Minuten bei laufender GUI.
- Bei wenig freiem Speicher: gleiche Altersgrenzen; Abbruch, sobald die eingestellte
  Kapazität verfügbar ist. Ohne zuverlässig lesbare Kapazität wird nicht gelöscht.

Workspace-Alter, Log-Aufbewahrung und Mindestkapazität werden über den vorhandenen
AppPreferencesStore gespeichert. Änderungen der Richtlinie während einer laufenden
Bereinigung verhindern weitere Löschungen. Erfolgreiche Bereinigungen und Fehler
werden im Audit-Log erfasst. Vor der ersten möglichen Löschung wird ein Start-Eintrag
dauerhaft gespeichert. Bei Abbruch bleibt dieser erhalten und die Vorschau wird
verworfen; ein Abschluss-Eintrag bestätigt erst die endgültigen Zähler.

## Bewusste Grenzen gegenüber dem Mockup

Globale DerivedData-Ordner und Host-Caches werden nicht automatisch analysiert
oder gelöscht: Andere Xcode-Prozesse können sie verwenden. Eine belastbare
Zuordnung zu Runner-Jobs fehlt derzeit. Eine pauschale „kein Runner busy“-Prüfung
würde dafür nicht reichen. Auch importierte Dokumente-Ordner bleiben unberührt.

Die Funktion beendet oder entlädt selbst keine Runner. Die Engine-Steuerung aus
v0.6.0 ergänzt den dafür nötigen Bedienweg. Bei noch geladenen LaunchAgents kann
eine Vorschau deshalb Kandidaten zeigen, die bei der Bereinigung übersprungen
werden; entfernte und übersprungene Einträge werden getrennt gezählt.
