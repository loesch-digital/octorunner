# Cache & Storage — nächster v0.5.0-Schritt

Die bestehende Settings-Navigation und das akzeptierte Kartenlayout werden um
den sechsten Tab ergänzt. Persistierte StoragePolicy-Werte bekommen reale Wirkung.

1. Tab-/Suchtest zuerst rot; Cleaner-Tests verwenden ausschließlich temporäre
   Fixture-Verzeichnisse. Produktionsdaten werden in Tests nie gelöscht.
2. WorkspaceCleanerActor misst logische Dateigrößen für Workspaces, Actions,
   Temp und Diagnose-Logs. APFS-freigegebene Blöcke werden nicht erfunden.
3. Reinigung nur in unmittelbaren Runner-Unterordnern des verwalteten AppSupport-
   Verzeichnisses. Keine importierten Ordner, Symlinks oder externen Host-Caches.
   Alte Diagnose-Logs behalten mindestens die neueste Datei. Reservierte Tools,
   Runner-Konfiguration und Binärdateien bleiben geschützt.
4. Vor jeder Löschung: Identität und Alter erneut prüfen, keine Listener/Worker,
   LaunchAgent tatsächlich entladen. IDLE reicht nicht. Unbekannter Prozess- oder
   Agentzustand überspringt die Löschung. Cancellation beendet weitere Mutationen.
5. Settings: bewusst gestartete Analyse, echte Kategorien/Volumenwerte,
   Bereinigungsvorschau und Bestätigung, sichtbare Fehler und Audit-Einträge.
   Manuell ist Standard; explizite automatische Richtlinien bearbeiten nur diese
   verwalteten Pfade. Dokumente-Zugriff bleibt bis zum konkreten Bedarf aus.
6. DE/EN, A11y, NSHostingView bei schmaler/breiter Ansicht und Light/Dark;
   native Kategorie-UI-Tests um den sechsten Tab ergänzen. Dann Swift/Python/Build,
   Review, PR-CI, Merge und main-CI.

Bewusst konservativ: Globale DerivedData-/Host-Caches werden nicht automatisch
gelöscht, da andere Xcode-Prozesse sie nutzen können. Die spätere Engine-Steuerung
muss Start und Bereinigung koordinieren; der Cleaner akzeptiert heute nur bereits
entladene und prozessfreie Runner.

## Ausführungsnachweise

- Tab/Suche zuerst rot (3 Erwartungen), Cleaner zuerst rot (6 Erwartungen).
- Cleaner-Regression: Dateiänderung während zweiter Zustandsprüfung rot → erneute
  synchrone Prüfung nach dem await.
- Review: Symlink-Vorfahren, kanonische Dienstnamen und Audit bei Teilabbruch.
  Für alle drei Regressionstests vor den Fixes ausgeführt. POSIX lstat folgt
  Links bei abschließendem Slash; Metadatenprüfung entfernt den Verzeichnis-Hint.
- Entscheidung: Keine globalen Host-Caches löschen; fehlende Prozesszuordnung
  würde fremde Builds gefährden. Diese Grenze ist in docs/15 dokumentiert.
- Entscheidung: Vor jeder möglichen Bereinigung dauerhaftes Audit-Intent speichern,
  Abschluss bestätigt Zähler. Abbruch invalidiert Vorschau ohne Modelzugriffe
  nach Cancellation. Exakte Zähler werden bei Teilabbruch nicht behauptet.
- Abschluss lokal: 255 Swift-Tests/54 Suites mit Code Coverage grün, 18 Python-
  Tests grün, Xcode-Debug-Build grün. Cleaner 98,1 % Zeilenabdeckung,
  Zustandsprüfung 100 %, Controller 72,3 %. Der 10-Minuten-Lifecycle und alle
  interaktiven Sheet-Zweige sind damit nicht vollständig automatisch abgedeckt.
- Visuell: Settings-Captures DE/EN, 620/960 Punkte, Light/Dark geprüft; bestehende
  Kartenstruktur und sichtbare sechs Kategorien bleiben erhalten. Native
  Kategorie-Auswahl inklusive Storage läuft zusätzlich in der PR-CI.
