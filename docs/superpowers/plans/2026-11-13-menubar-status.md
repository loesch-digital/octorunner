# Menüleistenlogo und Busy-Erkennung

Nutzerfreigabe: OctoRunner-Logo mit vorgeschaltetem Statuspunkt umsetzen. Bestehende Statusfarben, VoiceOver-Text und Hover-Hilfe beibehalten. Bei „Ohne Farben unterscheiden“ eindeutige Statussymbole verwenden. Die vorhandene SVG-Geometrie dient als skalierbare Vorlage; kein Rasterbild und keine erneute TimelineView im Menüleisten-Label.

Live-Befund: Listener unter bin/Runner.Listener, aktiver Worker unter bin.2.338.2/Runner.Worker. Der lokale Sampler erkennt nur den exakten Ordner bin und zeigt deshalb IDLE.

- [x] Regression für gemischte/versionierte Binary-Ordner, getrennte Runner und falsche Dateinamen: rot, dann minimale Parserkorrektur, grün.
- [x] Bildregression für transparentes Logo plus getrennten Statuspunkt in Light/Dark und unterscheidbare Statussymbole: rot, dann Vektorgeometrie aus docs/assets/menubar_icon.svg zeichnen, grün.
- [x] Vollständige Swift-/Python-Tests, nativer Starttest, Debug-Build und visuelle Bildkontrolle.
- [ ] Feature-Branch pushen, PR-CI bis grün beobachten; erst anschließend Beta-Abschluss wieder aufnehmen.

Ergebnis: 234 Swift-Tests und 18 Python-Tests grün, Debug-Build erfolgreich. Die gemeldete Versionierungs-Kombination wurde erst rot reproduziert. Der echte korrigierte Sampler liefert für den laufenden Listener/Worker busy=true. Vergleichsbilder sämtlicher Zustände in Light/Dark geprüft. Rein lesendes unabhängiges Review ohne wichtige Befunde. GUI muss zum Laden des neuen Builds regulär neu gestartet werden.
