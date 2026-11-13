# Audit-Log

Der Toolbar-Eintrag **Audit Log** öffnet die lokale Ereignishistorie. Die Ansicht zeigt neue Ereignisse zuerst und bietet kombinierbare Filter für Kategorie, Schweregrad, exakten Runner-Namen und eine Suche in Titel und Beschreibung. Entfernte Runner bleiben über ihren gespeicherten Namen auffindbar.

Zunächst werden bis zu 200 Treffer geladen. **Weitere Ereignisse laden** erweitert die Ansicht jeweils um 200 Treffer. Die Suche berücksichtigt die gespeicherte Historie, nicht nur die bereits geladenen Einträge. Ein Klick auf ein Ereignis öffnet seine vollständigen Details einschließlich Ereignis-ID, Konto und Vorher-/Nachher-Werten, sofern vorhanden.

**Angezeigte Ereignisse exportieren …** speichert genau die aktuell geladenen, gefilterten Ereignisse als JSON mit Schema-Version 1 und ISO-8601-Zeitstempeln. Der Inhalt wird vor dem Speicherdialog eingefroren. Für ältere Einträge zuerst weitere Ereignisse laden. Erst beim Export wird ein Speicherort gewählt; das Öffnen der Historie durchsucht keine Benutzerordner.

Die App ergänzt bestehende Authentifizierungs-, Konfigurations- und Runner-Ereignisse um App-Start/-Ende, Update-Beginn/-Erfolg/-Fehlschlag und erkannte lokale Prozessstatuswechsel. Initiale Statusmessungen erzeugen keine künstlichen Wechsel. Runner-Prozessstatus und Workflow-Job-Ergebnis bleiben getrennte Informationen. Eine Beendigung durch einen erzwungenen Prozessabbruch kann keinen regulären App-Ende-Eintrag garantieren. Die vollständige Crash-Erkennung durch den Supervisor gehört zu v0.6.0.

Die neuen System- und Update-Einträge speichern festgelegte Metadaten ohne Token, Download-URLs oder ungefilterte Fehlermeldungen. Der Export enthält die sichtbaren Audit-Informationen; gespeicherte Runner-Namen, Kontonamen und Konfigurationswerte sind entsprechend vor einer Weitergabe zu prüfen.

## Prüfung

- SwiftData-Filter einschließlich kombinierter Filter, Suche und Ladegrenze.
- JSON-Snapshot einschließlich Unicode, Zeilenumbrüchen, stabiler Identität und Zeitstempeln.
- App-/Update-Ereignisse und Prozessstatuswechsel ohne doppelte Baseline-Einträge.
- NSHostingView-Layout mit echter Fensteranbindung für leere/gefüllte Historie bei 680 und 1100 Punkten, DE/EN sowie Hell/Dunkel.
- Nativer UI-Test für Öffnen, Filtern, Zurücksetzen, Details und Schließen; Ausführung in der CI.
