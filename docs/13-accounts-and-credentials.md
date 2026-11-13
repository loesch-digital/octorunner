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

„Auth & Tokens“ ist über die Einstellungen im Hauptfenster und über die native
Settings Scene erreichbar. Der ausgewählte Account steht zuerst. Die Ansicht
unterstützt Verbinden, erneute Anmeldung, Accountauswahl und bestätigtes Trennen.
Sie lädt keine Token-Inhalte beim Öffnen und zeigt weder erfundene Ablaufdaten
noch einen unimplementierten Touch-ID-Schalter. Auth-Anfragen verwenden die anhand
der [GitHub-Dokumentation](https://docs.github.com/en/rest/about-the-rest-api/api-versions)
verifizierte REST-Version `2026-03-10`; ungültige Token-Zeichen werden vor dem
Aufbau eines HTTP-Credential-Headers verworfen.

NSHostingView-Tests und geprüfte Render-Abbilder decken leere Ansichten und 80
Accounts mit langen Namen/Rechten bei 620 und 900 Punkten, Deutsch/Englisch sowie
Light/Dark ab. Die native Dialoginteraktion mit echten Accounts ist noch manuell
abzunehmen:

- Hauptfenster: Einstellungen öffnen; zusätzlich ⌘, und den Auth-Tab prüfen.
- Zwei Testaccounts verbinden, auswählen und prüfen, dass Jobs und Wizard den
  ausgewählten Account verwenden. Erneute Anmeldung derselben Identität ersetzt
  deren Zugangsdaten, eine andere Identität wird separat hinzugefügt.
- PAT-/Geräteanmeldung starten, abbrechen und erneut öffnen; keine späte
  Erfolgsmeldung, kein gelöschter oder unbeabsichtigt gewechselter Account.
- „Account trennen …“ zunächst abbrechen, dann für einen Testaccount bestätigen.
  Der andere Account und laufende Runner-Dienste bleiben erhalten.
- Bei fehlenden OAuth-Scope-Headern bleiben Rechte ausdrücklich unbekannt; Tokens
  und Ablaufdaten werden nicht vorgetäuscht.

Offen sind die interaktive Abnahme und die übrigen Step-5-Bereiche, insbesondere
Storage, vollständige Telemetrie und Audit-UI. Dieser Stand ist noch kein
vollständiges v0.5.0.
