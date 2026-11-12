# Jobs-Historie: Daten und Kennzahlen

In Arbeit für v0.5.0. API, Persistenz und Kennzahlen sind implementiert; die
Jobs-Oberfläche und deren Lade-/Accountwechselsteuerung folgen noch.

Der neue Actions-Client liest ausschließlich Workflow-Runs und Jobs über GET.
Er fordert keine zusätzlichen Schreibrechte an. Weiterleitungen werden abgelehnt;
Pagination bleibt auf HTTPS, `api.github.com` und dem angefragten Repository samt
Endpoint beschränkt. Rate-Limit und Retry-After kommen aus tatsächlichen Headern.
Fehler enthalten Statuscodes statt Serverantworten oder Zugangsdaten.

Accounts, Repositories, Workflow-Runs, Run-Versuche und einzelne Matrix-Jobs haben
getrennte Identitäten. Fehlt die Versuchszahl, bleibt sie unbekannt. Sobald ein
bekannter Versuch vorliegt, verdrängt er den unbekannten Snapshot in der sichtbaren
Workflow-Liste und den Kennzahlen. Alte Versuche bleiben gespeichert. Remote-Historie
speichert Runner-Metadaten als Snapshot; das Entfernen eines lokalen Runners löscht
sie nicht. Die bestehende Cascade-Beziehung lokaler Legacy-Jobs bleibt erhalten.

Die Kennzahlen beschreiben nur das geladene Historienfenster:

- Ein Workflow wird im jeweils neuesten bekannten Versuch einmal gezählt; seine
  Matrix-Jobs erhöhen die Workflow-Anzahl nicht.
- Erfolgsquote: `success / (success + failure + timed_out + startup_failure + action_required + stale)`.
  Abgebrochene, übersprungene, neutrale und unbekannte Ergebnisse gehen nicht in
  diese Quote ein. Ohne auswertbare Ergebnisse gibt es keinen Prozentwert.
- Durchschnittliche Dauer: abgeschlossene Workflows mit tatsächlich bekannter
  Dauer, unabhängig von ihrer Conclusion. Fehlende oder negative Intervalle werden
  ausgeschlossen. Legacy-Dauern bleiben erhalten.
- Dauer-SLA: Anteil der bekannten Dauern innerhalb eines ausdrücklich angegebenen
  Zeitlimits. Ohne Zeitlimit oder Stichprobe bleibt der Wert unbekannt. Diese
  Kennzahl bewertet Laufzeit, nicht erfolgreichen Abschluss.
- „Heute abgeschlossen“ verwendet bekannte Abschlusszeiten und den übergebenen
  Kalender. Fehlende Zeitwerte werden nicht durch den aktuellen Zeitpunkt ersetzt.

GitHubs `updated_at` ist kein Abschlusszeitpunkt. Ein Workflow-Ende wird deshalb
erst aus der vollständigen Job-Liste mit bekannten Abschlusszeiten abgeleitet.
Partielle Seiten oder laufende Jobs erzeugen keine abgeschlossene Workflow-Dauer.

Die Migrationsprüfung kopiert eine echte SQLite-Datei aus dem v0.4-Schema und
öffnet sie direkt mit dem erweiterten SwiftData-Schema. Accounts, Runner,
Job-Beziehungen, Audit-Einträge und gespeicherte Werte müssen erhalten bleiben.
Der Test verwendet keine automatische Löschung oder Neuerstellung des Stores.
Zusätzlich prüft er, dass neue Historien-Einträge nach der Migration gespeichert
und in einem frischen ModelContext wieder gelesen werden können.

Lokaler Zwischenstand vom 12. November 2026: 113 Swift-Tests grün mit
Coverage-Instrumentierung; Zeilenabdeckung Historien-Store 99 %, Kennzahlen 100 %,
Historienfilter rund 97 % und Actions-Client rund 97 %. Diese Werte betreffen die
SPM-Datenlogik. Sie ersetzen weder die noch ausstehende Jobs-UI-Abnahme noch einen
Test aller unterstützten macOS-Versionen oder der vollständigen Anwendung.
