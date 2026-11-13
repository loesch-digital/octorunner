# Audit-Log-Dialog — v0.5.0

Der freigegebene Plan verlangt Filter nach Kategorie/Schwere/Runner und Export.
Die Umsetzung bleibt bei SwiftData, bestehenden Theme-Karten und DE/EN. Ein
Toolbar-Button öffnet eine resizable Sheet-Ansicht; keine neue Sidebar-Rubrik.

1. Tests zuerst rot: reale SwiftData-Filter, begrenztes Laden, DTO-Export mit
   Unicode/ISO-Datum, NSHostingView für Empty/volle Listen in Light/Dark.
2. Dynamischer FetchDescriptor nur mit gespeicherten Feldern. Initial 200
   Ereignisse, „Mehr laden“ schrittweise; neueste zuerst. Keine unbeschränkte
   Startabfrage. Filter und Suche laufen in der Datenbank.
3. Auswahl zeigt sämtliche Ereignisdetails inkl. Vorher/Nachher. Export friert
   die angezeigten Zeilen als Value-Snapshot ein, JSON über nativen Save-Dialog.
   Kein automatischer Ordnerzugriff und kein Clipboard-/Netzwerkexport.
4. App-Start/-Ende und Update-Start/-Fehler ergänzen; vorhandene Auth-, Import-
   und Konfigurationsereignisse bleiben erhalten. Crash-Erkennung gehört zum
   Supervisor-Schritt v0.6.0 und wird hier nicht als geliefert dargestellt.
5. DE/EN, Accessibility und Resize-Captures; Swift/Python/Build. Ein unabhängiges
   Branch-Review, PR-CI, Merge und main-CI abwarten.

Entscheidung: Export heißt ausdrücklich „Angezeigte Ereignisse exportieren“.
Damit exportiert er exakt den sichtbaren gefilterten Ausschnitt, statt unbemerkt
mehr Datensätze oder Daten aus anderen Filtern zu speichern. Mehr laden erweitert
auch den Export. Historische Daten und gespeicherte Texte werden nicht verändert.
