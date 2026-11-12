# Jobs-Historie: Daten und Kennzahlen

In Arbeit für v0.5.0. API, Persistenz, Kennzahlen und Lade-/Accountwechselsteuerung
sind implementiert und an die Jobs-Ansicht im Hauptfenster angebunden.
Die vollständige v0.5.0 bleibt in Arbeit.

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
- Live-Zähler für laufende und wartende Workflows benötigen eine Beobachtung aus
  den letzten 90 Sekunden. Ältere offene Zustände werden getrennt als veraltet
  gezählt; die Historie behält ihren zuletzt beobachteten Status.

Der Loader lädt zehn Workflow-Runs pro Seite und alle zugehörigen Job-Seiten
(höchstens 20 pro Versuch; zyklische Pagination wird abgelehnt). Vollständig
geladene, abgeschlossene Versuche verwenden ihre gespeicherten Job-Details weiter.
Laufende Versuche werden erneut abgefragt. Fehlende Versuchszahlen werden nicht
durch einen geschätzten ersten Versuch ersetzt.

Account- und Auswahlwechsel sowie Cancellation verwerfen verspätete Daten vor
jedem SwiftData-Zugriff. Rate-Limit-Metadaten gehören dagegen zur jeweiligen
Antwort und ihrem Account: Eine spät eintreffende Sperre bleibt auch nach einem
Auswahlwechsel erhalten und verkürzt keine bereits bekannte längere Wartezeit.
Ein Repositorywechsel umgeht die Kontosperre nicht; andere Accounts bleiben
nutzbar. Bei ausgeschöpftem Budget werden keine weiteren Job-Abfragen gesendet.
Partielle Details gelten dabei nicht als vollständig geladen.

Vor einem neuen Aufruf werden sowohl `Retry-After` als auch der Reset eines
ausgeschöpften Budgets beachtet. Fehlt ein brauchbarer Servertermin, beginnt die
Wartezeit bei einer Minute und verdoppelt sich bei erneuten Limit-Fehlern bis auf
eine Stunde. Der Loader startet selbst keine automatischen Wiederholungen.
Siehe [GitHubs Regeln für Rate-Limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).

GitHubs `updated_at` ist kein Abschlusszeitpunkt. Ein Workflow-Ende wird deshalb
erst aus der vollständigen Job-Liste mit bekannten Abschlusszeiten abgeleitet.
Partielle Seiten oder laufende Jobs erzeugen keine abgeschlossene Workflow-Dauer.

Die Migrationsprüfung kopiert eine echte SQLite-Datei aus dem v0.4-Schema und
öffnet sie direkt mit dem erweiterten SwiftData-Schema. Accounts, Runner,
Job-Beziehungen, Audit-Einträge und gespeicherte Werte müssen erhalten bleiben.
Der Test verwendet keine automatische Löschung oder Neuerstellung des Stores.
Zusätzlich prüft er, dass neue Historien-Einträge nach der Migration gespeichert
und in einem frischen ModelContext wieder gelesen werden können.

## Bedienung und Aktualisierung

In der Seitenleiste öffnet **Jobs & Workflow-Läufe** die Historie im vorhandenen
Hauptfenster. Filter für Status, Repository, Runner sowie Workflow/Branch/Commit
beziehen sich auf den jeweils neuesten bekannten Versuch. Job-Details werden
aufgeklappt; der GitHub-Link öffnet den zugehörigen Workflow samt Logs erst nach
bewusstem Klick. Links auf fremde Hosts oder andere Runs werden nicht angeboten.

**Historienquellen** übernimmt konkrete Repository-URLs der lokalen Runner.
Organisationen allein sind keine Repository-Quelle: zusätzliche `owner/repository`
oder GitHub-Repository-URLs ausdrücklich hinzufügen. Zusätzliche Quellen werden
pro aktivem Account gespeichert und können wieder entfernt werden; gespeicherte
Historie bleibt erhalten. Es werden weder alle Account-Repositories automatisch
aufgezählt noch neue GitHub-Schreibrechte angefordert.

Die Ansicht aktualisiert bei aktiver App alle 60 Sekunden die ersten zehn Läufe
pro ausgewählter Quelle. Ein explizit ausgewähltes Repository erlaubt außerdem
**Ältere Läufe laden**. Die Zeit der Beobachtung steht am einzelnen Lauf;
„Letzte Antwort“ bezieht sich auf die letzte geladene Quelle und ist keine Zusage,
dass jede gespeicherte Zeile gerade neu geladen wurde. Laufende ältere Seiten
können veralten und werden dann entsprechend gekennzeichnet.

Ein einzelner Repositoryfehler verhindert den Abgleich weiterer Quellen nicht;
die betroffenen Quellen werden gesammelt angezeigt. Authentifizierungsfehler,
Rate-Limits und Cancellation stoppen den Batch. Nach Fehlern pausiert die
automatische Aktualisierung bis zur bewussten Wiederholung. Aktive API-Sperren
bleiben beim Wechsel zwischen Runner- und Jobs-Ansicht sowie beim Neuerstellen
eines Jobs-ViewModels erhalten: der gemeinsame Budgetzustand lebt in AppServices.

Das Dauerziel ist standardmäßig nicht konfiguriert. Ein ausgewähltes Ziel wird
persistent gespeichert. Kennzahlen respektieren die aktuellen Filter und zeigen
bei fehlenden Messungen einen Strich statt einer erfundenen Null oder 100 Prozent.

## Prüfung

Lokaler Zwischenstand vom 12. November 2026: 141 Swift-Tests mit
Coverage-Instrumentierung und zehn Python-Tests grün; vollständiger Xcode-Debug-Build
erfolgreich. Zeilenabdeckung Historien-Store 99 %, Kennzahlen 100 %, Historienfilter
97 %, Loader 100 %, Lade-ViewModel 99 %, Budgetzustand und History-Preferences
100 %. Die reine Jobs-Darstellung wird über NSHostingView bei 560 und 900 Punkten
in Light/Dark mit langen Namen, 80 Repository-Auswahlen und 80 Job-Snapshots geprüft.
Deutsche und englische Statusdarstellung sowie sichere GitHub-Links haben eigene Tests.

Diese Werte ersetzen keine interaktive Abnahme der vollständigen Anwendung und
keinen Test aller unterstützten macOS-Versionen. Noch manuell prüfen:

1. Quellen aufklappen, ein lesbares Test-Repository hinzufügen und wieder entfernen.
2. Status-, Repository-, Runner- und Suchfilter kombinieren; schmale/breite Fenster prüfen.
3. Jobs aufklappen und den Workflow-Link bewusst öffnen.
4. Für ein Repository ältere Läufe laden; ohne SLA-Ziel muss der SLA-Wert unbekannt bleiben.
5. Account wechseln und während des Ladens zurück zum Dashboard navigieren;
   keine Daten des vorherigen Accounts und keine Fehlermeldung allein durch Abbruch.
6. Bei einem echten API-/Berechtigungsfehler die sichtbare Fehlermeldung und pausierte
   Aktualisierung prüfen. Keine echten Limits absichtlich durch viele Requests provozieren.
