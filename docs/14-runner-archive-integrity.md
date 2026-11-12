# Integritätsprüfung der Runner-Archive

Stand: Feature-Branch für v0.5.0, noch nicht veröffentlicht.

Vor der Nutzung eines Archivs benötigt OctoRunner eine gültige SHA-256-Prüfsumme.
Leere oder fehlerhafte Prüfsummen gelten nicht als erfolgreiche Verifikation.
Die Bytes werden sowohl bei vorhandenen Cache-Dateien als auch bei neuen
Downloads geprüft. Die Berechnung liest jeweils höchstens 64 KiB pro Block und
berücksichtigt Task-Abbrüche zwischen den Blöcken.

Die Quelle wird folgendermaßen bestimmt:

1. Die Download-Metadaten müssen ein offizielles macOS-ARM64-Archiv unter
   `github.com/actions/runner/releases/download/<Tag>/<Dateiname>` identifizieren.
   Pfadbestandteile, fremde Ziele, URL-Zugangsdaten und Query-Parameter werden
   nicht akzeptiert.
2. Eine mitgelieferte gültige `sha256_checksum` wird verwendet.
3. Fehlt sie, fragt OctoRunner den exakt zugehörigen öffentlichen Release über
   `api.github.com/repos/actions/runner/releases/tags/<Tag>` ab. Dafür wird kein
   Account-Token gesendet; zusätzliche OAuth-Rechte sind nicht erforderlich.
4. Release-Tag, stabiler Veröffentlichungsstatus, Asset-Name, Download-URL und
   Asset-Status müssen übereinstimmen. Genau ein passendes Asset mit gültigem
   `sha256:`-Digest ist erforderlich. Erfolgreiche Auflösungen werden begrenzt im
   Speicher zwischengespeichert.

Bei fehlenden, widersprüchlichen oder nicht erreichbaren Metadaten bricht die
Einrichtung ab. Ein unbestätigtes Archiv wird nicht installiert. Die
Vertrauensbasis bilden die GitHub-API über TLS und die offiziellen
`actions/runner`-Release-Daten. Die Prüfung liefert keine zusätzliche unabhängige
Herausgeber-Attestierung.

Ein beschädigter neuer Download ersetzt keinen bestehenden Cache-Eintrag.
Temporäre Dateien werden nach der Prüfung aufgeräumt. Fehlertexte übernehmen
weder private Transportdiagnosen noch Download-URLs, die durch Weiterleitungen
temporäre Zugangsdaten enthalten könnten.

## Verifikation

Die Tests verwenden unabhängige SHA-256-Vektoren (`abc` und eine Million `a`),
kontrollierte HTTP-Metadaten sowie einen echten lokalen HTTP-Server für
erfolgreiche, beschädigte und fehlgeschlagene Downloads. Fehlende Prüfsummen,
Pfad-/URL-Grenzen, anonyme Requests, falsche Releases, doppelte Assets,
Rate-Limit-/HTTP-Fehler und verspätete Antworten nach Abbruch sind abgedeckt.
Es werden ausschließlich synthetische Test-Zugangsdaten verwendet.

Die Absicherung der verwalteten Verzeichnisse gegen Symlinks und parallele
Dateisystemänderungen bleibt Teil der noch offenen Storage-/Pruning-Arbeiten.
Diese Integritätsprüfung ersetzt jene Verzeichnis- und Lebenszyklusregeln nicht.

Grundlagen: [Runner-Download-API](https://docs.github.com/en/rest/actions/self-hosted-runners),
[Release- und Asset-Metadaten](https://docs.github.com/en/rest/releases/releases).
