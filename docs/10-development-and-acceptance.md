# Entwicklungsstand auf dem Mac abnehmen

Eine Abnahme braucht keine Homebrew-Installation der App:

| Zweck | Weg | Prüfung |
| --- | --- | --- |
| Unveröffentlichter Branch | Debug-Build aus Xcode | Aktueller Quellstand, Debugger und Logs |
| Fertiges Release ohne Homebrew | Signiertes ZIP aus GitHub Releases | Ausgelieferte App, Signatur und Notarisierung |
| Abschließender Installationstest | Homebrew-Upgrade | Cask, Download, Prüfsumme und Upgrade |

## 1. Lokal aus Xcode starten

Voraussetzungen sind ein vollständiges aktuelles stabiles Xcode und XcodeGen. Am 2026-11-11 geprüft: Xcode 27.2 mit Swift 6.4.2; siehe [Toolchain-Prüfung](09-pipeline-privacy-and-test-audit.md). XcodeGen lässt sich auch ohne Homebrew installieren; die [offizielle Anleitung](https://github.com/yonaskolb/XcodeGen#installing) beschreibt Make und Swift Package Manager.

1. Die installierte OctoRunner-App über **Quit** vollständig beenden; das Schließen des Dashboard-Fensters reicht nicht.
2. Den abzunehmenden Branch auschecken und den Commit mit `git rev-parse HEAD` festhalten.
3. Im Repo Tests ausführen und das Projekt erzeugen:

   ```sh
   swift test --package-path Packages/OctoRunnerKit --no-parallel
   python3 -m unittest discover -s scripts/tests
   swift scripts/generate-app-icons.swift
   xcodegen generate
   ```

4. `OctoRunner.xcodeproj` in Xcode öffnen. Scheme **OctoRunner**, Ziel **My Mac**, Run-Konfiguration **Debug** wählen.
5. Für einen lokalen Start ohne Entwicklerzertifikat bei Bedarf im Target unter **Signing & Capabilities** das Zertifikat **Sign to Run Locally** wählen. Lokale Änderungen am generierten Projekt werden bei `xcodegen generate` überschrieben; dauerhafte Projekteinstellungen gehören in `project.yml`.
6. Mit **⌘R** bauen und starten. Mit **⌘.** den Debugger-Lauf beenden. Den regulären Quit-Dialog zusätzlich über **Quit** in der App prüfen.

Die App startet aus Xcodes Build-Verzeichnis und wird nicht nach `/Applications` installiert. Dafür sind weder Match-Secrets noch Notarisierung nötig. [Apple beschreibt „Sign to Run Locally“ als Ad-hoc-Signierung](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

**Die Daten sind derzeit nicht isoliert:** Debug und Release verwenden dieselbe Bundle-ID `io.octorunner.macos`, denselben SwiftData-Speicher, dieselben Preferences und Keychain-Service-Namen. Runner-Aktionen und Änderungen wirken auf den vorhandenen Bestand. Einen Modus mit Beispieldaten gibt es bisher nicht. Für isolierte Abnahmen einen separaten macOS-Testbenutzer mit eigenen Test-Runnern verwenden. Keychain- oder Ordnerfreigaben können wegen der abweichenden lokalen Signatur erneut nötig sein; Debug-Freigaben belegen nicht das Verhalten des signierten Releases.

### Alternativ im Terminal bauen

Nach der Projekterzeugung:

```sh
xcodebuild -project OctoRunner.xcodeproj \
  -scheme OctoRunner \
  -configuration Debug \
  -derivedDataPath DerivedData/Development \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build
```

Danach liegt die App unter `DerivedData/Development/Build/Products/Debug/OctoRunner.app` und kann im Finder geöffnet werden. Auch hierfür zuerst die installierte App beenden. Lokale Ad-hoc-Builds sind nicht zur Weitergabe an andere Macs bestimmt.

## 2. Signiertes Release ohne Homebrew starten

1. Unter [GitHub Releases](https://github.com/loesch-digital/octorunner/releases) das gewünschte `OctoRunner-<Version>-arm64.zip` herunterladen. Der aktuelle Release-Build erfordert Apple Silicon und macOS 15 oder neuer.
2. ZIP entpacken und eine laufende OctoRunner-App vollständig beenden.
3. Die entpackte App im Finder öffnen. Sie kann vor der Installation aus dem entpackten Ordner geprüft werden. Für die normale Installation die App nach `/Applications` ziehen; beim späteren Wechsel zu Homebrew eine vorhandene manuelle Installation berücksichtigen.
4. Developer-ID-Freigabe prüfen, beispielsweise für die installierte App:

   ```sh
   spctl --assess --type execute -vv /Applications/OctoRunner.app
   ```

Erwartet wird `accepted` mit `source=Notarized Developer ID`. Bei Ablehnung die Ursache untersuchen; weder Quarantäneattribute löschen noch Gatekeeper abschalten.

## 3. Abnahme vor der Veröffentlichung

Die lokale Abnahme des Feature-Branches erfolgt vor Merge und Release-Tag. Commit, macOS, Xcode-Version und Testergebnis festhalten. Anschließend bleiben grüne PR-CI, grüne main-CI und der signierte Release-Lauf verbindlich. Das finale Homebrew-Upgrade prüft den zusätzlichen Vertriebsweg.

Für den aktuellen Patch prüfen:

- Start ohne vorsorglichen Dokumente-Zugriff; externe Runner erst über **Import Folder…** auswählen, externe Logs erst bewusst öffnen oder aktualisieren.
- **Dashboard** oben rechts im Menüleistenfenster mehrfach verwenden, auch bei minimiertem oder geschlossenem Fenster: genau ein Dashboard.
- Fenster schließen: Menüleisteneintrag bleibt. **Quit** abbrechen: App bleibt. **Quit** bestätigen: App und Menüleisteneintrag verschwinden.
- Runner mit installiertem LaunchAgent laufen weiter. Für nicht migrierte importierte Runner erklärt der Quit-Dialog die Einschränkung.
- GitHub-Login und Runner-Verwaltung mit den benötigten Rechten; fehlende Token-Scope-Header dürfen keine erfundenen Freigaben anzeigen.

Prüfstand am 2026-11-11: Der Debug-Build über den obigen CLI-Befehl war erfolgreich. Für v0.4.4 waren 37 Swift-Tests, 9 Python-Tests, PR-/main-CI, Release mit Notarisierung, Homebrew-Upgrade und Gatekeeper erfolgreich. Der Nutzer hat anschließend genau ein Dashboard trotz fünfmaligem Öffnen, Schließen/Wiederöffnen, Quit, normalen Neustart ohne Dokumente-Abfrage und die deaktivierten Vorschau-Schalter bestätigt. Der neue externe Ordnerimport und das Weiterlaufen konkreter Runner sind damit noch nicht separat belegt. Die Computersteuerung meldet weiterhin `cgWindowNotFound`; der Xcode-Connector wartet auf eine Freigabe über sein Menüleistensymbol. Ein erfolgreicher Build wird nicht als erfolgreicher interaktiver Start ausgegeben.
