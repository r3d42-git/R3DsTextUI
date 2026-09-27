# TextUI

**Deutsch** · [English](README.en.md)

Ein schlanker, nativer Texteditor für macOS 15 und neuer auf Apple Silicon.
TextUI konzentriert sich auf `.txt`, `.md` und `.html`, mehrere Dateien in Tabs und zuverlässige Wiederherstellung ungespeicherter Arbeit.

**Status: frühe Version 0.1.1.** Öffentliches Projekt unter **GPL-3.0-or-later**. Sichtbarer App-Name: **TextUI**; Bundle-Name: **R3Ds TextUI**; stabile Bundle-ID: `com.r3d42.textui`.

[Downloads und Versionshinweise](https://github.com/r3d42-git/R3DsTextUI/releases) · [Lizenz](LICENSE) · [Lizenzumfang und Drittanbieter](LICENSING.md)

Zur Installation das Release-ZIP entpacken und `TextUI.app` in den Programme-Ordner ziehen. Unterstützt werden ausschließlich Apple-Silicon-Macs ab macOS 15. Öffentliche Release-Pakete werden mit Developer ID und Hardened Runtime signiert, bei Apple notarisiert und enthalten die App mit angeheftetem Notarisierungsticket.

## Umfang des Erstentwurfs

- Native Texteingabe mit AppKit, automatischer Formaterkennung über die Dateiendung sowie DokuWiki-Erkennung anhand des Inhalts von `.txt`-Dateien. Syntaxhervorhebung für Markdown, DokuWiki und HTML einschließlich eingebettetem CSS. Dunkelblaue Editorpalette im dunklen Modus, angepasste helle Palette im hellen Modus.
- Mehrere Dateien in Tabs, Zeilennummern, Cursorposition und Auswahlumfang.
- Gehe zu Zeile, Dokumentgliederung, Schriftgröße und Zeilenumbruch.
- Suchen und Ersetzen mit Groß-/Kleinschreibung, ganzen Wörtern und regulären Ausdrücken.
- Bewusstes Speichern mit `⌘S`, laufende lokale Entwurfssicherung und optionales automatisches Speichern bereits benannter Dateien.
- Zuschaltbare Markdown-, DokuWiki- und HTML-Vorschau (⌥⌘P) neben dem Quelltext. Markdown unterstützt unter anderem Tabellen, Aufgabenlisten und Codeblöcke. Aktualisierung nach kurzer Schreibpause; Dokumentskripte und Netzwerkzugriff sind deaktiviert. Weblinks öffnen sich erst nach Rückfrage im Standardbrowser; Code lässt sich per Kopierknopf übernehmen.

49 automatisierte Core- und Editortests bestehen; Start, grundlegende Bearbeitung, Suche, Entwurfswiederherstellung und eine HTML-Datei mit 2.500 Zeilen wurden lokal geprüft. Weitere Details und offene Prüfungen stehen in `PROJECT_SUMMARY.md`.

Die Entwurfssicherung ersetzt keine externe Datensicherung. Insbesondere Dateikonflikte, Wiederherstellung nach Abstürzen und die Bedienung bleiben Gegenstand weiterer Tests.

## Speichern und Schließen

`⌘S` schreibt Änderungen in die gewählte Datei. Neue Dokumente erhalten dabei über den Dateidialog einen Namen und Speicherort. Die Entwurfssicherung hält unabhängig davon den Arbeitsstand im lokalen Benutzerprofil vor.

Beim Schließen eines geänderten Tabs fragt TextUI nach **Speichern**, **Verwerfen** oder **Abbrechen**. Verwerfen entfernt auch den Entwurf dieses Tabs. Beim Schließen des Fensters oder Beenden der App bleibt die offene Sitzung zur Wiederherstellung erhalten. Automatisches Speichern ist standardmäßig ausgeschaltet.

## Lokal entwickeln

Voraussetzungen: Apple Silicon, macOS 15 oder neuer und Xcode mit einer Swift-6-fähigen Toolchain. SwiftPM lädt die in `Package.resolved` festgeschriebenen Markdown-Abhängigkeiten.

```sh
./script/build_and_run.sh
```

Das Skript beendet eine laufende TextUI-Instanz regulär, baut für `arm64`, erstellt `dist/TextUI.app`, signiert sie lokal ad hoc und öffnet sie. Es erzwingt keinen Prozessabbruch. Die lokale Signatur ist keine Developer-ID-Signatur und keine Notarisierung für die Verteilung an andere Macs.

```sh
./script/build_and_run.sh --build-only
./script/build_and_run.sh --verify
swift test --arch arm64
```

`--verify` prüft nach dem Start nur, ob der Prozess läuft. Weitere Modi: `--debug`, `--logs` und `--telemetry`. GitHub Actions führt Tests und einen lokalen Bundlebuild aus. Signierung und Veröffentlichung laufen separat lokal über die Release-Skripte.

## Projektstruktur

- `Sources/TextUI`: AppKit-Anwendung und Editoroberfläche.
- `Sources/TextUICore`: unabhängig von der Oberfläche prüfbare Text- und Sitzungslogik.
- `Tests/TextUICoreTests`: automatisierte Kerntests.
- `Resources/Info.plist`: App-Metadaten und unterstützte Dateiendungen.
- `script/build_and_run.sh`: lokaler Build- und Startweg.
- `PROJECT_SUMMARY.md`: Entscheidungen, Übergabe und offener Prüfbedarf.

## Datenschutz und Veröffentlichung

Quelltext und Dokumentation enthalten keine benötigten privaten Zugangsdaten, Signieridentitäten oder absoluten persönlichen Dateipfade. Buildprodukte und lokale Entwicklungsdaten gehören nicht ins Repository. Nutzerdateien, echte Entwürfe und lokale Sitzungsdaten dürfen weder als Testdaten noch als Fehleranhang eingecheckt werden.

TextUI steht unter GPL-3.0-or-later; Drittanbieterhinweise bleiben erhalten. Details: `LICENSING.md`.

## Bewusste Grenzen

Das Ziehen von Tabs zur Umsortierung folgt später; aktuell lassen sich Tabs über das Navigationsmenü verschieben. Die Vorschau lädt weder externe noch lokale Bild-/CSS-Dateien und führt keine Skripte aus dem Dokument aus. Die app-eigenen Kopierknöpfe laufen getrennt vom Dokument. Unterstützte Kodierungen sind UTF-8 und UTF-16 mit BOM; andere Kodierungen werden ausdrücklich abgelehnt. Regex-Ersetzungen behandeln den Ersatztext wörtlich.

Sitzungen einschließlich ungespeicherter Texte liegen lokal unter `~/Library/Application Support/com.r3d42.textui/Session.json`. Sie werden nicht hochgeladen.

## Markdown-Parser

Die Vorschau verwendet Swift Markdown 0.7.3 und swift-cmark 0.9.0. Versionen und Revisionen sind in `Package.resolved` festgehalten. Die zugehörigen Lizenz- und Copyright-Hinweise liegen in `Resources/ThirdPartyNotices` und werden ins App-Bundle übernommen. Beim ersten Build lädt SwiftPM diese Abhängigkeiten; die Vorschau selbst arbeitet offline.

## DokuWiki-Texte

TextUI erkennt typische DokuWiki-Inhalte in `.txt`- und endungslosen Dateien automatisch anhand mehrerer Merkmale in den ersten 32.768 Zeichen. `.wiki` und `.dokuwiki` werden direkt erkannt; explizite Markdown-/HTML-Endungen haben Vorrang. Einzelne Zeichenfolgen oder ein einzelnes Codebeispiel genügen bewusst nicht. Die Statusleiste zeigt das erkannte Format an.

Vorschau, Syntaxfarben und Gliederung unterstützen die gebräuchliche Grundsyntax: Gleichheitszeichen-Überschriften, Code-/Dateiblöcke, erzwungene Umbrüche, Hervorhebungen, Wiki-Links, Listen, Tabellen und Zitate. Code und Nowiki-Bereiche werden nicht als Überschriften ausgewertet. Wiki-Plugins, Serverfunktionen und Medienauflösung sind nicht enthalten; interne Wiki-Ziele werden als Beschriftung angezeigt. Der Quelltext, die Endung und die Dateikodierung bleiben beim Betrachten unverändert.

## Release erstellen und prüfen

Auf einem Mac mit vorhandener Developer-ID-Identität und eingerichtetem `notarytool`-Schlüsselbundprofil `TextUI`:

```sh
./script/release.sh 0.1.1
./script/verify_release.sh 0.1.1 dist/release/0.1.1/TextUI-0.1.1-macOS-arm64.zip
git push -u origin main
# Den erfolgreichen GitHub-CI-Lauf für diesen Commit abwarten.
./script/publish_release.sh --dry-run 0.1.1
./script/publish_release.sh 0.1.1
```

`release.sh` verlangt einen sauberen, committed Quellstand, führt alle Tests aus, baut optimiert, signiert, notarisiert und heftet das Ticket vor der ZIP-Erstellung an. `SIGNING_IDENTITY` und `NOTARY_PROFILE` erlauben lokale Überschreibungen. Zugangsdaten bleiben ausschließlich im Schlüsselbund. Ein bestehendes Release-Ausgabeverzeichnis wird nicht überschrieben. Bei unterbrochener Notarisierung erst den vorhandenen Auftrag anhand der Submission-ID bzw. Notarisierungshistorie prüfen; nicht erneut hochladen.

`verify_release.sh` entpackt das übergebene ZIP frisch und prüft Version, Bundle-ID, Architektur, Lizenzdateien, Signatur, Hardened Runtime, Ticket und Gatekeeper. `publish_release.sh` verlangt sauberes `main`, passenden Quellcommit, erfolgreichen GitHub-CI-Lauf dieses Commits, öffentliches Zielrepository und einen freien Tag. Nach Upload lädt es ZIP und Prüfsumme erneut herunter, gleicht auch den GitHub-Digest ab und prüft die heruntergeladene App. Die Skripte benötigen Zugriff auf Netzwerk, Schlüsselbund und macOS-Sicherheitsdienste; eine eingeschränkte Sandbox kann diese Zugriffe blockieren.
