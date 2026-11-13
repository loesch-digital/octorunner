# Runner-Zustand und Job-Ergebnis

Vom Nutzer bestätigte Darstellung: Runner bleibt IDLE/grün oder RUNNING/blau,
auch wenn ein Job fehlschlägt. Separat erscheinen letzter abgeschlossener lokaler
Job, Ergebnis, Abschlusszeit und sicherer GitHub-Link. Menüleiste erhält ein
zusätzliches Fehlersymbol für nicht quittierte Fehler der geladenen Historie.
Quittierung bleibt über App-Neustarts erhalten und verändert keine Job-Ergebnisse.

## Umsetzung

1. Roter NSHostingView-Test: aktiver lokaler Runner mit fehlgeschlagenem Job
   muss in der Menüansicht zusätzlich zur grünen Bereitschaft einen roten
   Job-Hinweis zeigen (Light/Dark).
2. Getestete Auswahl aus GitHub-Snapshots: aktiver Account, exakte Runner-ID und
   Repository-/Organisationsscope, eindeutige lokale Identität, neuester Versuch.
   Keine Zuordnung anhand von Namen und keine fremden Account-Daten.
3. Gemeinsame SwiftData-Quelle und persistente Quittierung; separate Anzeige
   im Dashboard und Menü, zusätzliches Symbol neben dem unveränderten Statuslogo.
   Kein TimelineView im Menüleistenlabel.
4. DE/EN, VoiceOver, schmale Layouts und echte NSHostingView-Captures prüfen.
5. Swift-/Python-Suite, Debug-Build, PR, CI abwarten, Merge und main-CI prüfen.

## Grenzen und anschließender Plan

Keine Logzeilen als verbindliches Job-Ergebnis; vorhandene GitHub-Historie wird
wiederverwendet. Ohne geladene Daten bleibt das letzte Ergebnis unbekannt.
Vorhandenes opt-in Hintergrundpolling und Mitteilungsrechte bleiben erhalten;
die Jobs-Ansicht erlaubt bewusstes Aktualisieren auch ohne Mitteilungen.
Danach weiter mit fehlendem Cache-&-Storage-Tab des v0.5.0-Plans.

## Lokale Validierung

- NSHostingView-Regression zuerst rot in Light und Dark (fehlender roter Hinweis).
- Laufende Wiederholung und Singularübersetzung ebenfalls zuerst rot reproduziert.
- 241 Swift-Tests / 50 Suites und 18 Python-Tests grün; Debug-App gebaut.
- Captures der Menüansicht und Runner-Zeile in beiden Erscheinungsbildern geprüft.
- Readonly-Review ohne wichtige Findings; Query-Hülle im Menülabel ohne
  Zustandsmutation und ohne TimelineView. Lokaler interaktiver Scene-Start bleibt
  gesonderte Abnahme; Renderingtests ersetzen diese Aussage nicht.
