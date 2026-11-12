# Accounts und Zugangsdaten — Zwischenstand für v0.5.0

Die Authentifizierung speichert Tokens ausschließlich im macOS-Keychain. SwiftData
enthält Account-Metadaten und nicht geheime Lookup-Schlüssel. Angezeigte OAuth-Scopes
stammen aus GitHubs Antwort; fehlende Scope-Header bei Fine-grained PATs bedeuten
unbekannte Rechte, nicht automatisch `repo`, `workflow` oder `admin:org`.

Neue Credentials erhalten einen eigenen Schlüssel aus unveränderlicher GitHub-ID
und einer Versions-ID. Ein umbenannter oder erneut vergebener Login überschreibt
dadurch keinen fremden Token. Bestehende Login-Schlüssel bleiben lesbar; erneutes
Anmelden stellt den Account um und behält alte Schlüssel für gezielte Bereinigung.
Die App veröffentlicht immer höchstens einen aktiven Account. Wizard, Runner-Sync,
Label-Updates und Jobs verwenden dessen gespeicherten Schlüssel.

Schließen des Login-Dialogs bricht Gerätecode-, PAT- und Polling-Anfragen ab.
Verspätete Antworten dürfen weder Zwischenablage noch Account-Daten ändern.
Bereits gespeicherte, noch nicht übernommene Credentials werden gezielt verworfen.
Schlägt das Speichern der Metadaten fehl, werden nur die Auth-Änderungen restauriert;
andere ausstehende Änderungen im gemeinsamen ModelContext bleiben erhalten.

Abmelden entfernt zuerst aktuelle und frühere Credentials dieses Accounts, danach
Metadaten und Erfolgs-Audit. Von anderen Accounts referenzierte Lookup-Schlüssel
bleiben bestehen. Fehler werden angezeigt; es gibt keinen vorzeitigen Erfolgs-Audit.
Eine währenddessen erneuerte Anmeldung bleibt durch eigene Credential-Version und
Metadatenprüfung erhalten. Lokales Abmelden widerruft keine Tokens bei GitHub und
stoppt keine bereits eingerichteten Runner-Dienste.

Automatisierte Regressionen prüfen unter anderem wiedervergebene Logins,
Legacy-Cleanup, Abbruch direkt nach Keychain-Save, verspätete Antworten,
Accountwechsel, parallele Abmeldung und Savefehler einschließlich eines späteren
erfolgreichen Context-Saves. Die Keychain-Integration nutzt ausschließlich
synthetische Werte in jeweils eigenen UUID-Testservices.

Offen in diesem Zwischenstand: Auth-&-Tokens-Settings-Ansicht und interaktive
Abnahme mit echten Accounts. Dieser Stand ist noch kein vollständiges v0.5.0.
