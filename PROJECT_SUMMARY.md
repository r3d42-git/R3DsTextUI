# TextUI – Projektstand und Übergabe

Stand: 2026-09-27. Öffentliche Erstveröffentlichung vom Nutzer autorisiert: Repository, Commit/Push, GPL-Lizenz sowie Signierung und Notarisierung. Die älteren Abschnitte dokumentieren den historischen Entwicklungsstand.

## Vereinbarter Produktumfang

Native macOS-App ab macOS 15, Apple Silicon only. Sichtbarer Name **TextUI**, `CFBundleName` **R3Ds TextUI**, stabile Bundle-ID `com.r3d42.textui`.

Fokus: `.txt`, `.md`, `.html`, automatische Formatwahl nach Dateiendung, Tabs, Zeilennummern, Navigation in langen Dokumenten, schnell erreichbare Schriftgröße und Zeilenumbruch, Cursorstatus, leistungsfähige Suche und Ersetzen. Typische längere Nutzerdateien liegen bei rund 2.500 HTML-Zeilen.

Vorschau ist erwünscht, darf den Editor jedoch nicht überladen. Die lokale Vorschau unterstützt HTML und Markdown ohne JavaScript oder Netzwerkzugriff. Synchrones Vorschau-Scrollen und umfassendere Vorschau-Ressourcenverwaltung können später folgen.

## Verbindliche Speicherregeln

- Bewusstes Speichern per `⌘S` ist der Standard.
- Lokale Entwurfssicherung läuft unabhängig vom Speichern der Originaldatei.
- Offene Tabs, ungespeicherte Dokumente und Cursorpositionen sollen Fenster-/App-Schließen und Rechnerneustart überstehen.
- Einzelnen geänderten Tab schließen: **Speichern / Verwerfen / Abbrechen**.
- Verwerfen entfernt bewusst auch den gesicherten Entwurf des Tabs.
- Unveränderte Tabs schließen ohne Nachfrage.
- Optionales automatisches Speichern ist anfangs ausgeschaltet; unbenannte Dokumente bleiben Entwürfe bis zur Dateiauswahl.
- Extern veränderte Dateien dürfen nicht still überschrieben werden.

## Technischer Aufbau

Swift Package mit AppKit-Executable `TextUI`, einer `TextUICore`-Bibliothek und zugehörigem Testtarget. Swift-6-Toolchain, zunächst Swift-5-Sprachmodus. Native Texteingabe über `NSTextView`; Swift Markdown und swift-cmark für die Vorschau.

`script/build_and_run.sh` erzeugt `dist/TextUI.app` für `arm64` und eine lokale Ad-hoc-Signatur. Standardmäßig reguläres Beenden einer laufenden App, Build und Start. Keine erzwungenen Prozessabbrüche, damit Sitzungen gespeichert werden können. `--build-only` erzeugt das Bundle ohne Start; `--verify` prüft nur den laufenden Prozess. Die Zusatzmodi `--debug`, `--logs`, `--telemetry` dienen der Entwicklung.

## GitHub- und Datenschutzgrenzen

Der Nutzer hat am 2026-09-27 das öffentliche Repository `r3d42-git/R3DsTextUI`, Commit und Push aller Projektänderungen sowie die signierte und notarisierte Distribution autorisiert. Lizenz: GPL-3.0-or-later; Drittanbieterhinweise bleiben erhalten. Keine Nutzerdateien, echten Entwürfe, Tokens oder privaten Schlüssel einchecken.

Releaseprofil: SwiftPM, `main`, Version 0.1.0 (Build 1), Apple Silicon arm64, macOS 15+, Bundle-ID `com.r3d42.textui`. Lokale Developer-ID-Signierung mit Hardened Runtime, Schlüsselbundprofil `TextUI`. `script/release.sh` erzeugt das ZIP erst nach angenommener Notarisierung und Stapling der App. `verify_release.sh` prüft die frisch entpackte App; `publish_release.sh` prüft Quellcommit, freien Tag, öffentliches Repository und den späteren GitHub-Download samt Digest. CI baut und testet ohne Signiergeheimnisse.

## Validierung am 2026-09-27

- Vollständiger arm64-App-Build erfolgreich; App-Bundle gestartet, Prozess sowie native Oberfläche geprüft.
- 13 XCTest-Kerntests bestanden: UTF-8/UTF-16 mit BOM, Unicode/CRLF-Byte-Roundtrip, extern geänderte/gelöschte Dateien, Speichern, Session-Roundtrip, Literal-/Regex-/Ganzwortsuche und Navigation.
- Manuelle App-Prüfung: Texteingabe, Zeilennummern, Trefferzählung und Treffernavigation, Speichern als Markdown inklusive automatischer Formaterkennung, Dialog Speichern/Verwerfen/Abbrechen und Abbrechen, Beenden/Neustart mit ungespeichertem Entwurf und Cursorposition.
- Synthetische HTML-Datei mit 2.500 Zeilen geöffnet, Syntaxfarben und HTML-Vorschau sichtbar geprüft; Sprung zu Zeile 2450 erfolgreich. Ein anfänglicher Scrollversatz wurde durch Stabilisierung des Textlayouts und Normalisierung des Dokumentursprungs behoben; erneute Öffnung bei Zeile 1 bestätigt. Dabei aufgetretene horizontale Überlagerung durch die Nummernspalte korrigiert: horizontalen Dokumentursprung erhalten, nur vertikal normalisieren. Vollständige Zeilenanfänge bei 14 und 22 pt visuell geprüft, ebenso Umbruchumschaltung.
- Lokale Ad-hoc-Signatur und plist geprüft, Binärdatei ist ausschließlich arm64. Quelltext-/Konfigurationsprüfung auf persönliche absolute Pfade, typische Token-/Private-Key-Muster und nachgestellte Leerzeichen ohne Befund.
- Lokales Git initialisiert, kein Remote und kein Push. Keine Lizenz festgelegt. GitHub-CI vorbereitet, dort noch nicht ausgeführt.

## Grenzen und nächste Schritte

- Markdown- und HTML-Vorschau verwenden eine feste 50/50-Aufteilung mit dem Editor (visuell geprüft) und zeigt eingebettetes CSS und Datenbilder; Dokumentskripte, Netzwerk sowie lokale Bild-/CSS-Dateien sind gesperrt; Weblinks können nach Bestätigung extern geöffnet werden. Noch kein vollständiger Browser-Kompatibilitätstest.
- Syntaxhervorhebung und Gliederung sind einfache Regex-Regeln, keine vollständigen Sprachparser. Markdown-Gliederung kann Überschriften in Codeblöcken erfassen. Regex-Ersetzungen verwenden wörtlichen Ersatztext, keine Capture-Group-Expansion.
- Unterstützte Dateikodierungen: UTF-8 (mit/ohne BOM), UTF-16 LE/BE mit BOM. Andere Kodierungen werden abgelehnt, nicht still konvertiert. Neue Zeilen übernehmen LF/CRLF/CR; eingefügter fremder Text kann gemischte Zeilenenden enthalten.
- Tabs sind über das Navigationsmenü umsortierbar; Drag-and-drop-Umsortieren folgt später.
- Optionale automatische Speicherung ist implementiert, aber noch nicht umfassend mit UI-Abläufen abgenommen. Dasselbe gilt für Verwerfen/Speichern im Schließen-Dialog, Ersetzen/Rückgängig, Finder-Kaltstart, Fenster-Schließen und Fehlerfälle bei unzugänglicher Entwurfssicherung.
- App-Neustart ist geprüft; echter Rechnerneustart, Stromausfall und Ausführung auf macOS 15 wurden nicht getestet. Deploymentziel bleibt macOS 15.
- UI ist ein funktionaler nativer Erstentwurf; App-Icon, genauer visueller Feinschliff, Notarisierung und öffentliche Distribution stehen aus.

## Lokale Daten

Sitzung unter `~/Library/Application Support/com.r3d42.textui/Session.json`, Einstellungen in der zugehörigen UserDefaults-Domain. Sitzung enthält Entwurfstexte, Originalbytes zur Konflikterkennung, Dateipfade, Cursor- und Scrollpositionen. Diese Daten bleiben lokal und liegen außerhalb des Repositorys. Defekte Sitzungen werden vor einem neuen Start separat gesichert, sofern das Dateisystem dies erlaubt.

Synthetische QA-Dateien und lokale Testprotokolle liegen ausschließlich im ignorierten `.local/qa/`. Buildausgabe liegt im ignorierten `dist/`. Bei der nächsten Iteration zuerst dieses Dokument lesen und die tatsächlichen Dateien prüfen.

## Editor-Stil nach Screenshotvorlage

Der Editor hat jetzt eine dunkelblaue Palette mit gedämpftem Grundtext, Cyan für HTML-Tags/CSS-Eigenschaften, Orange für Attribute/Selektoren/Funktionen/Hexfarben, Grün für Strings und Violett für Zahlen/Einheiten. Helle Systemdarstellung hat eine entsprechende helle Palette. Menlo Regular mit etwas mehr Zeilenabstand, dezente Zeilennummern, Markierung der aktuellen Zeile und flachere Tabs. Syntaxfarben werden weiterhin nur als temporäre Layoutattribute angewendet. CSS wird innerhalb von HTML-style-Blöcken erkannt; dies bleibt ein leichter Tokenizer und kein vollständiger Sprachparser.

Die vom Nutzer gemeldete Überlagerung links unten wurde durch explizites Clipping im Ruler sowie in ScrollView und Editorhost behoben. Sichtprüfung an der geöffneten HTML-Datei, nach Scrollen sowie bei 20 und 24 pt: Nummern und Text bleiben oberhalb der Statusleiste. Die Datei wurde dabei nicht bearbeitet. Ursprüngliche Schriftgröße 20 pt wiederhergestellt.

Vollständiger `swift test --arch arm64`: 20 Tests bestanden, davon sieben neue Syntax-Tests für HTML/CSS-Abgrenzung, String-/Kommentarpriorität, unvollständige style-Blöcke und UTF-16-Positionen. Arm64-App neu gebaut und gestartet.

## Performance und Nummernspalte

Anlass: eine portable HTML-Datei mit rund 11,2 MB, 1.907 physischen Zeilen und einer rund 4,7 Millionen Zeichen langen Einzelzeile. Bei Zoom wurden vorher alle Tabs gestylt, komplette Layouts erzwungen und Syntax wiederholt neu erkannt.

Aktueller Stand: Schrift-/Umbruchänderungen werden gecacht und nur auf den aktiven Tab angewendet; andere Tabs übernehmen sie beim Aktivieren. Die Schriftgröße wird über „TextUI → Einstellungen …“ (⌘,) oder „Schrift …“ in der Statusleiste gewählt und erst mit „Übernehmen“ angewendet. Der Slider und direkte Zoomaktionen wurden auf Nutzerwunsch entfernt; Abbrechen ändert nichts. TextKit darf nicht zusammenhängende sichtbare Bereiche berechnen, vollständiges ensureLayout/sizeToFit entfällt. Die Nummernansicht fragt nur sichtbare Zeilen an. Syntaxerkennung ist asynchron mit Versionsprüfung; der HTML-Scanner überspringt eingebettete Script-Inhalte sequenziell statt sie zuerst nach HTML zu durchsuchen. Umbruch und Syntaxfarben bleiben auch bei großen Dokumenten verfügbar; keine größenabhängige Abschaltung.

Die Nummernspalte ist jetzt eine eigene, begrenzte View neben dem ScrollView statt eines nativen überlagernden Rulers. ScrollView und dessen ContentView clippen ausdrücklich. Darstellung im realen 11-MB-Dokument bei 12 und 20 pt geprüft: Text und Nummern bleiben getrennt, CSS-Farben vorhanden. Bedienprüfung 12→20→12: ca. 1,2 bzw. 1,0 Sekunden einschließlich UI-Automation und Zustandsabfrage, keine isolierte Renderzeit. Nutzerdatei nicht verändert.

26 Tests bestanden: 22 Core-Tests plus vier native Editortests (große eingebettete Daten behalten Umbruch/Farben, Zoom ohne Dokumentänderung, kein erneuter Syntaxpass bei Zoom, geometrischer Abstand und Clipping der Nummernspalte). Synthetischer HTML-Tokenizer-Test >11 MB: etwa 0,038 Sekunden. Diese Messung betrifft den Tokenizer, nicht die gesamte Darstellung. Extrem lange Einzelzeilen und alle Scroll-/Bearbeitungsfälle sind noch nicht vollständig profiliert.

## Markdown-Farben nach Screenshotvorlage

Markdown-Überschriften erscheinen grün, starke Hervorhebungen (`**…**` / `__…__`) rot/pink. Eingebettetes HTML verwendet Cyan für Tags, Orange für Attribute und Grün für Werte. Normaler Text, Listen und Tabellen behalten den grauen Grundton. Inline-Code und Codeblöcke haben Vorrang vor enthaltenem HTML und Hervorhebungen. Eigene semantische Tokens erhalten die bisherigen HTML/CSS-Farben unverändert.

28 Tests bestanden (24 Core, vier native Editortests), einschließlich neuer Markdown-Fälle mit eingebettetem HTML, Unicode/CRLF und Codepriorität. App neu gebaut und gestartet; Farben im geöffneten Markdown-Dokument visuell geprüft. Dokumentinhalt nicht geändert.

## Initialer Zeilenumbruch

Die Umbruchbreite wird jetzt nach dem Einbetten des Editors, bei unverändertem Umbruchstatus und bei Größenänderungen des Viewports mit dessen tatsächlicher Breite abgeglichen. Damit bleibt eine vorläufige Dokumentbreite nicht bis zum manuellen Aus-/Einschalten bestehen. Der Abgleich ändert nur abweichende Geometrie und startet keinen Syntaxpass.

29 Tests bestanden. Neuer nativer Test prüft echte Zeilenfragmente bei mehreren Fensterbreiten und korrigiert gezielt einen simulierten überbreiten Ausgangsframe ohne Umbruchumschaltung. Das ursprüngliche Problem ließ sich im einfachen isolierten Layouttest nicht reproduzieren. Nach dem Fix eine synthetische Markdown-Datei frisch über den Öffnen-Dialog geladen: langer Absatz bricht direkt um, ohne den Umbruchknopf zu bedienen. Testtab wieder geschlossen, vorherige Nutzerdatei bleibt geöffnet.

## Markdown-Vorschau

Der Vorschau-Button und Darstellung → Vorschau (⌥⌘P) unterstützen jetzt Markdown und HTML. Markdown wird mit Swift Markdown 0.7.3 / swift-cmark 0.9.0 in einer seriellen Hintergrundqueue gerendert. Versionen sind festgeschrieben, Drittanbieterhinweise liegen im Repository und App-Bundle. Änderungen werden nach 650 ms Schreibpause übernommen; eine Generationskennung verhindert veraltete Ergebnisse nach Änderungen, Tabwechseln oder Ausblenden.

Unterstützt: Überschriften, Hervorhebungen, Listen/Aufgabenlisten, Tabellen, Zitate, Codeblöcke, Links und eingebettetes HTML. Responsive helle/dunkle Gestaltung. Dokumentskripte, Netzwerk und lokale externe Ressourcen bleiben gesperrt. Weblinks können inzwischen nach Bestätigung im Standardbrowser geöffnet werden. Keine synchronisierte Scrollposition; bei Aktualisierung beginnt die Vorschau wieder oben.

Validierung: bisherige 29 Tests plus fünf neue Renderer-Tests bestanden. Arm64-Bundle gebaut und gestartet. Die geöffnete Markdown-Anleitung zeigt Überschriften, Tabellen und Listen neben dem korrekt umgebrochenen Quelltext. Synthetische Testdatei bestätigt Code-/HTML-Darstellung und automatische Aktualisierung nach Texteingabe. Teständerung verworfen und Testtab geschlossen, Nutzerdateien nicht bearbeitet.

## DokuWiki-Unterstützung

DokuWiki wird in .txt-, endungslosen und unbenannten Dokumenten anhand mehrerer Merkmale innerhalb der ersten 32.768 Zeichen erkannt (zwei unabhängige Merkmale oder zwei Überschriften). .wiki/.dokuwiki sind explizit; .md/.html behalten Vorrang. Format wird aus dem aktuellen Entwurf abgeleitet, auch nach Sitzungswiederherstellung. Nach Bearbeitung gleicht der vorhandene verzögerte Aktualisierungspfad Syntax, Gliederung und Vorschau ab. Kein neues Dateiformat beim Speichern und keine Änderung der Session-Struktur.

DokuWikiSyntax liefert Farben und UTF-16-Gliederungspositionen; Code/file/nowiki/%%-Bereiche sind davon ausgenommen. DokuWikiPreview unterstützt Grundsyntax für Überschriften, Hervorhebungen, Links, Listen, Tabellen, Umbrüche, Zitate und literale Codebereiche. Gleiche Offline-WebView und Vorschaugestaltung wie Markdown. Wiki-Plugins, Medienauflösung und interne Seitenauflösung bleiben ausgenommen. HTML wird escaped. Einzeiliger Code innerhalb von Listeneinträgen wird inline dargestellt, mehrzeiliger Code als Block.

Validierung: 44 Tests bestehen (39 Core + fünf native Editorprüfungen); neue Tests für konservative Erkennung, UTF-16-Gliederung, Literalpriorität, Vorschau und byteidentisches Speichern/Wiederherstellen einer UTF-16/CRLF-.txt-Datei. Nach letzten Renderer-Anpassungen zehn DokuWiki-bezogene Tests erneut bestanden. App gebaut und gestartet; geöffnete Nutzer-.txt wird als DokuWiki erkannt und zeigt Überschriften, Links, nummerierte Listen und Code korrekt in der Vorschau. Gliederungsmenü enthält die vier erwarteten Überschriften. Nutzerdatei nicht bearbeitet.

Buildskript kopiert Drittanbieterhinweise jetzt mit install -m644, damit wiederholte Builds nicht an schreibgeschützten Quelldateirechten scheitern. Erfolgreicher Bundlebuild und Signaturprüfung bestätigt.

## Links und Codekopie in der Vorschau

Echte Klicks auf HTTP-/HTTPS-Links zeigen eine native Rückfrage mit vollständiger Zieladresse. Abbrechen ist die Standardaktion; erst die ausdrückliche Auswahl „Im Browser öffnen“ übergibt die URL an NSWorkspace/Standardbrowser. Andere App-/Dateischemata und URLs mit eingebetteten Zugangsdaten bleiben gesperrt. Dokumentanker bleiben intern. Automatische Navigation wird weiterhin blockiert.

PreviewCodeCopy fügt bei jeder Vorschau Codeblock- und Inline-Code-Kopierknöpfe hinzu. Das app-eigene WKUserScript läuft in defaultClient, getrennt von gesperrten Dokumentskripten. Kopiertext wird vor Einfügen der Controls erfasst; der native Handler schreibt nur Strings bis 10 MiB aus dem Hauptframe. Der Eventhandler verlangt einen echten Benutzerklick, Rückmeldung über „Kopiert“/„Nicht kopiert“.

Validierung: insgesamt 48 Tests bestanden (41 Core + sieben native), inklusive URL-Regeln, bytegenauem Kopiertext auf privater Testzwischenablage und echter WKWebView mit CSP/abgeschalteten Dokumentskripten. Initialer Testfehler durch falschen async-Overload korrigiert, beide Kopiertests danach erfolgreich. Arm64-App gebaut und gestartet. UI: Link-Rückfrage mit vollständiger URL und Abbrechen geprüft; Codeblock per Button kopiert und in einem temporären Tab eingefügt, einschließlich Einrückungen/Backslashes/Zeilenenden. Testtab verworfen; Nutzerdatei unverändert. Externes Browseröffnen wurde bei diesem UI-Test bewusst nicht ausgelöst.

## Vorbereitung der Erstveröffentlichung

Release-Skripte, GPL-Lizenz samt explizitem „oder später“, README und Versionshinweise ergänzt. App-Icon einschließlich Quellen vorhanden und im Bundle enthalten. Lokale Entwicklungsdateien `.local`, `.build` und `dist` bleiben ignoriert. Die Sandbox konnte Schlüsselbund und GitHub nicht erreichen; identische Prüfungen im freigegebenen lokalen Kontext bestätigten gültige Developer-ID-Identität und funktionierendes Profil `TextUI`. Keine Änderung an Schlüsselbund oder globalen Einstellungen nötig.

Noch nicht belegt: Start auf einem fremden/sauberen Mac, echte macOS-15-Laufzeit und Rechnerneustart. Frühere UI-Prüfungen oben gelten weiterhin nur für die jeweils getesteten Abläufe.
