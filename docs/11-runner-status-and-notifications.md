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

## Manuelle Abnahme

1. Entwicklungsstand ohne Homebrew nach [Entwicklungs- und Abnahme-Anleitung](10-development-and-acceptance.md) bauen und starten.
2. Bei kleiner und großer Fenstergröße lange Runner-Namen und viele Labels prüfen. **Live Log** öffnet das Protokoll gezielt; das Dashboard enthält keinen dauerhaften Logblock mehr.
3. **New Runner** mit vielen Repositories öffnen, Fenster verkleinern und nach unten scrollen. Abbrechen/Erstellen bleiben sichtbar. Die Startanzahl entspricht Repositories × Instanzen.
4. Mitteilungen bewusst aktivieren und in den macOS-Einstellungen zulassen. Einen ungefährlichen Test-Runner außerhalb laufender Jobs regulär starten/stoppen. Pro erkanntem Wechsel erscheint höchstens eine Meldung, entsprechend den Ereignisschaltern. Keine produktiven Jobs dafür abbrechen.
5. Dashboard schließen: Statusüberwachung bleibt aktiv. OctoRunner beenden: Menüleisteneintrag und Überwachung enden. Anschließend regulär neu starten: keine Statusmeldungsflut.

Automatisch geprüft sind Pfade mit Leerzeichen, unbekannte/veraltete Daten, Statuspriorität, Ereignisfilter und Duplikate, ältere Einstellungen, echte Prozessabfrage und das Verwerfen verspäteter Ergebnisse nach Abbruch. Interaktive Mitteilungsdarstellung, VoiceOver und die tatsächliche Menüleiste müssen auf dem angemeldeten Desktop zusätzlich abgenommen werden.
