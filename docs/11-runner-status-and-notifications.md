# Runner-Status und macOS-Mitteilungen

Stand: Implementierung auf dem Feature-Branch für v0.5.0; noch kein veröffentlichter Release.

Das Menüleistensymbol zeigt den zuletzt gemessenen **lokalen Prozesszustand**. Es ist keine Bestätigung der GitHub-Erreichbarkeit. Die App prüft alle 15 Sekunden die ausführbaren Listener-/Worker-Prozesse, ohne Runner-Ordner oder Protokolle dafür zu öffnen.

| Symbol | Bedeutung |
| --- | --- |
| Grüner Haken | Alle erfassten lokalen Runner sind aktiv. |
| Blaue Kreispfeile | Mindestens ein lokaler Runner arbeitet oder startet neu. |
| Orange Pause | Mindestens ein lokaler Runner ist gestoppt. |
| Rotes Ausrufezeichen | Ein erfasster Runner hat einen Fehlerstatus. |
| Graues Fragezeichen | Keine Runner, fehlgeschlagene Messung oder unvollständige/veraltete Statusdaten. |

Ein frischer Fehler-/Offline-Status hat Vorrang vor anderen Zuständen. Ohne vollständige frische Messungen wird nie grün angezeigt. Die Symbole unterscheiden sich auch ohne Farbwahrnehmung; VoiceOver erhält den Status als Text. Nach 60 Sekunden gelten Messungen als veraltet.

Die App-Einstellungen sind über das Zahnrad im Hauptfenster und über `⌘,` erreichbar. Unter **Mitteilungen** lassen sich macOS-Mitteilungen einschalten und Online-/Offline-Ereignisse getrennt auswählen. Beim ersten Aktivieren wird die Systemerlaubnis angefragt. Hintergrundmessungen fragen keine Erlaubnis an. Banner, Verlauf und Ton unterliegen weiterhin den macOS-Systemeinstellungen.

Online-/Offline-Mitteilungen beziehen sich auf lokale Prozesswechsel. Die erste Messung, wiederholte identische Messungen, Busy-/Idle-Wechsel und Messfehler erzeugen keine Meldungsflut. Nach einer fehlgeschlagenen Messung wird zunächst eine neue Ausgangslage erfasst. Neue Ereigniseinstellungen übernehmen bestehende Zustimmung und ausgeschaltete Ereignisse, aktivieren neue Ereignistypen aber nicht ungefragt.

**Fehlermeldungen sind bis zur tatsächlichen Crash-Erkennung in v0.6.0 ausdrücklich deaktiviert.** Die vorbereitete Ereignisverarbeitung kann Fehlerzustände verarbeiten; die aktuelle Prozessmessung kann aus dem Verschwinden eines fremden Prozesses keinen Exit-Code ableiten. Sie meldet deshalb keinen erfundenen Crash. Vollständige Crash-Erkennung, KeepAlive-/Quarantäne-Überwachung und der GitHub-Abgleich gehören zum nächsten Engine-Schritt.

Die Überwachung startet mit dem App-Lebenszyklus, läuft bei geschlossenen Fenstern weiter und endet beim Beenden der App. Installierte Runner-LaunchAgents bleiben davon unabhängig. Ein separater Hintergrund-Agent ist damit nicht implementiert.

## Speicherwarnungen

Alle 30 Sekunden liest die App ausschließlich die Kapazitätsmetadaten des Volumes,
auf dem das Home-Verzeichnis liegt. Es werden dafür keine Ordner aufgelistet oder
Dokumente geöffnet. Gemessen wird die von macOS für wichtige Daten verfügbare
Kapazität; sie kann auch von macOS freigebbaren Speicher enthalten. Werte bleiben
lokal. Der App-Build enthält dafür ein Privacy-Manifest mit Apples Grund `85F4.1`.

Der Ereignisschalter **Wenig freier Speicherplatz** und die allgemeine Zustimmung
zu Mitteilungen müssen eingeschaltet sein. Die Warnung erfolgt unter der
Storage-Policy-Grenze (derzeit standardmäßig 20 dezimale GB). Die Grenze ist im
Tab „Cache & Storage“ konfigurierbar (siehe [Speicherbereinigung](15-cache-and-storage.md)). Pro
Knappheitsphase erscheint eine Meldung. Erst bei mindestens 2 GB oberhalb der
Grenze wird eine neue Phase möglich. Messfehler und veraltete Daten gelten nicht
als Erholung; fehlgeschlagene Zustellungen können erneut versucht werden.

Nach bewusstem Aktivieren kann bereits bestehender Speichermangel gemeldet
werden. Es wird keine Systemerlaubnis automatisch angefragt und keine Datei
gelöscht. Ein beendeter App-Prozess verschickt keine neuen Warnungen.

## Fehlgeschlagene lokale Jobs

Nach Opt-in für **Lokaler Workflow-Job fehlgeschlagen** prüft die laufende App
auch bei geschlossenen Fenstern jüngste GitHub-Runs. Sie verwendet das in der
Historie konfigurierte Intervall (60–900 Sekunden) und dasselbe accountbezogene
Rate-Limit-Budget. Ohne allgemeine Zustimmung oder ohne diesen Ereignisschalter
werden durch den Monitor weder Zugangsdaten gelesen noch Requests gestartet.
Eine offene Jobs-Ansicht kann zusätzlich ihre eigene Aktualisierung ausführen;
die beiden Quellen teilen die Rate-Limit-Sperre, keinen vollständigen Request-Cache.

Repository-Runner liefern ihre Quellen aus dem gespeicherten Scope. Für
Organisationsrunner werden die gewünschten Repositories ausdrücklich unter
**Jobs → History sources** hinzugefügt. Nur eine passende GitHub-Runner-ID
**und** ein gültiger Repository-/Organisationsscope belegen eine lokale Zuordnung.
Namen allein, unbekannte IDs, mehrdeutige lokale Datensätze und das noch nicht
vereinheitlichte Personal-Multi-Repo-Modell führen zu keiner Meldung.

Der erste Check nach Start, Account-/Schlüsselwechsel oder erneutem Opt-in setzt
die zeitliche Ausgangslage. Bereits abgeschlossene Fehler bleiben dabei still;
die erste Ausgangslage kann bis zum nächsten eingestellten Poll dauern. Danach
werden neue abgeschlossene Jobs mit `failure` oder `timed_out` gemeldet, sofern
sie zum neuesten bekannten Attempt gehören. Abbrüche, übersprungene Jobs und
unbekannte oder widersprüchliche Abschlusszeiten erzeugen keine Fehlermeldung.
Die Mitteilung enthält den lokalen Runner-Namen und das Repository, keine
Job-Ausgabe oder privaten Transportdiagnosen.

Erfolgreich gemeldete Job-Identitäten werden für das aktuelle Opt-in und ein
rollierendes 24-Stunden-Fenster dedupliziert. Das berücksichtigt verspätet
beobachtete ältere Jobs und identische Abschlusszeitpunkte. Zustellfehler dürfen
erneut versucht werden. Auch ein Aus-/Einschalten zwischen zwei Polls verwirft
die vorherige Ausgangslage und verspätete Antworten. Account-, Quellen- und
Zustimmungsänderungen sowie Stop/Cancellation werden vor der Persistenz geprüft.

Dies ist ein begrenzter Poll der jüngsten zehn Runs pro Repository, keine
verlustfreie Push-Zustellung aller Ereignisse. Während die App beendet ist,
entstehen keine neuen Mitteilungen; hochfrequente Repositories oder längere
Netz-/API-Ausfälle können Ereignisse außerhalb dieses Fensters schieben. Die
vollständige ältere Historie bleibt bewusst über die Jobs-Ansicht ladbar.

## Manuelle Abnahme

1. Entwicklungsstand ohne Homebrew nach [Entwicklungs- und Abnahme-Anleitung](10-development-and-acceptance.md) bauen und starten.
2. Bei kleiner und großer Fenstergröße lange Runner-Namen und viele Labels prüfen. **Live Log** öffnet das Protokoll gezielt; das Dashboard enthält keinen dauerhaften Logblock mehr.
3. **New Runner** mit vielen Repositories öffnen, Fenster verkleinern und nach unten scrollen. Abbrechen/Erstellen bleiben sichtbar. Die Startanzahl entspricht Repositories × Instanzen.
4. Mitteilungen bewusst aktivieren und in den macOS-Einstellungen zulassen. Einen ungefährlichen Test-Runner außerhalb laufender Jobs regulär starten/stoppen. Pro erkanntem Wechsel erscheint höchstens eine Meldung, entsprechend den Ereignisschaltern. Keine produktiven Jobs dafür abbrechen.
5. Dashboard schließen: Statusüberwachung bleibt aktiv. OctoRunner beenden: Menüleisteneintrag und Überwachung enden. Anschließend regulär neu starten: keine Statusmeldungsflut.
6. Jobfehler-Mitteilungen aktivieren, passenden Repository-Scope beziehungsweise
   explizite Organisationsquelle konfigurieren und den ersten Check abwarten.
   Einen ungefährlichen neuen Test-Workflow auf diesem lokalen Runner fehlschlagen
   lassen. Erwartet: eine Meldung nach dem nächsten Poll, keine Wiederholung bei
   identischen Folgesamples. Erfolgreiche und abgebrochene Jobs bleiben still.

Automatisch geprüft sind Pfade mit Leerzeichen, unbekannte/veraltete Daten, Statuspriorität, Ereignisfilter und Duplikate, ältere Einstellungen, echte Prozessabfrage und das Verwerfen verspäteter Ergebnisse nach Abbruch. Interaktive Mitteilungsdarstellung, VoiceOver und die tatsächliche Menüleiste müssen auf dem angemeldeten Desktop zusätzlich abgenommen werden.

Speicherwarnungen sind mit injizierten Kapazitätsmessungen auf Grenzwerte,
Hysterese, Opt-in, Wiederholungen, DE-Formatierung und verspätete Ergebnisse
geprüft. Die native Volume-Abfrage und die periodische App-Lebenszyklus-Verkabelung
sind dadurch noch nicht vollständig automatisch abgedeckt. Den Datenträger zur
Abnahme nicht künstlich füllen; die tatsächliche Banner-Darstellung erfolgt im
normalen Betrieb oder mit einem kontrollierten Entwicklungs-Testadapter.
# Getrennte Runner-Zustände und Job-Ergebnisse

Der Runner-Zustand beschreibt die lokale Betriebsbereitschaft: IDLE/grün wartet
auf Arbeit, RUNNING/blau führt einen Job aus. Ein fehlgeschlagener Workflow-Job
verändert diesen Betriebszustand nicht.

Dashboard und Menü zeigen deshalb separat den **letzten abgeschlossenen Job**
mit Ergebnis, Abschlusszeit, Namen und Link zum GitHub-Lauf samt Versuch. Während
einer laufenden Wiederholung bleibt das vorherige abgeschlossene Ergebnis sichtbar.
Ohne belegbaren lokalen Job steht dort „Kein abgeschlossener Job geladen“.

Zusätzlich zum Statuspunkt und OctoRunner-Logo erscheint bei nicht quittierten
Job-Fehlern ein eigenes rotes Fehlersymbol in der Menüleiste. Dashboard und Menü
bieten „Diese Fehler quittieren“ an. Das speichert die konkreten Job-Identitäten
(Account, Repository, Run, Versuch, Job), statt nur einen Zeitcursor vorzustellen:
später eintreffende ältere Jobs bleiben erkennbar. Quittieren löscht weder Historie
noch das letzte Ergebnis und ändert keinen Runner-Zustand. Ältere Versuche werden
beim Fehlerzähler durch den neuesten bekannten Versuch ersetzt.

Die Anzeigen beziehen sich auf die **geladene GitHub-Historie**, nicht sämtliche
Läufe eines Accounts. Vorhandenes opt-in Hintergrundpolling für Job-Mitteilungen
bleibt erhalten; ohne dieses Opt-in lässt sich die Historie in „Jobs & Workflow-Läufe“
bewusst aktualisieren. Es werden keine zusätzlichen Rechte angefordert und keine
Runner-Logzeilen als verbindliche Job-Ergebnisse interpretiert. Zuordnung erfolgt
über aktiven Account, Runner-ID und exakten Repository-/Organisationsscope;
mehrdeutige Identitäten und reine Namensübereinstimmungen werden ausgeschlossen.
