# TextUI – Projektstand und Übergabe

Stand: 2026-09-28. JSON-Unterstützung vom Nutzer bestätigt; TextUI 0.1.2 (Build 3) öffentlich veröffentlicht und anhand eines frischen Downloads verifiziert. Beschreibung, deutsche/englische README und Archify-Seite sind aktualisiert. Die älteren Abschnitte dokumentieren den historischen Entwicklungsstand.

## Vereinbarter Produktumfang

Native macOS-App ab macOS 15, Apple Silicon only. Sichtbarer Name **TextUI**, `CFBundleName` **R3Ds TextUI**, stabile Bundle-ID `com.r3d42.textui`.

Fokus: `.txt`, `.md`, `.html`, `.json`, automatische Formatwahl nach Dateiendung, Tabs, Zeilennummern, Navigation in langen Dokumenten, schnell erreichbare Schriftgröße und Zeilenumbruch, Cursorstatus, leistungsfähige Suche und Ersetzen. Typische längere Nutzerdateien liegen bei rund 2.500 HTML-Zeilen.

Vorschau ist erwünscht, darf den Editor jedoch nicht überladen. Die lokale Vorschau unterstützt HTML, Markdown, DokuWiki und JSON ohne Dokumentskripte oder Netzwerkzugriff. Synchrones Vorschau-Scrollen und umfassendere Vorschau-Ressourcenverwaltung können später folgen.

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

Releaseprofil: SwiftPM, `main`, Version 0.1.2 (Build 3), Apple Silicon arm64, macOS 15+, Bundle-ID `com.r3d42.textui`. Lokale Developer-ID-Signierung mit Hardened Runtime, Schlüsselbundprofil `TextUI`. `script/release.sh` erzeugt das ZIP erst nach angenommener Notarisierung und Stapling der App. `verify_release.sh` prüft die frisch entpackte App; `publish_release.sh` prüft Quellcommit, freien Tag, öffentliches Repository und den späteren GitHub-Download samt Digest. CI baut und testet ohne Signiergeheimnisse.

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

## Veröffentlichter Release 0.1.0 – 2026-09-27

- Öffentliches Repository: https://github.com/r3d42-git/R3DsTextUI ; Lizenz GPL-3.0-or-later, von GitHub als GNU GPLv3 erkannt.
- Unveränderlicher Tag `v0.1.0`: Releasecommit `57a7776bd6d6fb0b69db53c5b0dc95956e76d99a`. Spätere Dokumentationscommits bewegen den Tag nicht.
- Release: https://github.com/r3d42-git/R3DsTextUI/releases/tag/v0.1.0 (öffentlich, kein Draft/Prerelease).
- Asset: https://github.com/r3d42-git/R3DsTextUI/releases/download/v0.1.0/TextUI-0.1.0-macOS-arm64.zip ; SHA-256-Datei daneben.
- ZIP SHA-256: `16a86a46446b5d8a2023a239908f593c80336539ca5f80a3cce0751a91315856`.
- Version 0.1.0, Build 1, arm64, macOS 15+, Bundle-ID `com.r3d42.textui`.
- Signatur: Developer ID Application, Philipp John Hild, Team `G6JH37W285`, sicherer Zeitstempel und Hardened Runtime.
- Apple-Submission `a0e4cf06-6306-42b1-aff0-004f2f0d438a`: `Accepted`. App vor Erstellung des finalen ZIP gestapelt.
- Lokal und aus frischem GitHub-Download: ZIP-Integrität, strict codesign, Identität, Version, Architektur, Lizenzdateien, stapler validate und Gatekeeper erfolgreich. Gatekeeper: `Notarized Developer ID`.
- Heruntergeladenes ZIP, lokale SHA-256-Datei und GitHub-Asset-Digest stimmen überein.
- 48 automatisierte Tests bestanden (41 Core, 7 native Editor-/Vorschautests). Prüfung auf typische Geheimnis-/Privatpfadmuster ohne Befund, `git diff --check` sauber. Eine überflüssige Schlussleerzeile im unverändert inhaltlich übernommenen Drittanbieter-NOTICE entfernt.
- Release-Skripte akzeptieren keine ungültigen Versionsangaben; negative Eingabeprüfung und vollständiger Publish-Dry-run bestanden.
- Kein Start auf sauberem fremden Mac und keine echte macOS-15-Laufzeitprüfung. Laufende lokale Entwicklung und Nutzersitzung wurden für den Release nicht ersetzt.

## macOS-15-Korrektur nach erstem CI-Lauf

Die Läufe https://github.com/r3d42-git/R3DsTextUI/actions/runs/36320053188 und https://github.com/r3d42-git/R3DsTextUI/actions/runs/36320054213 zeigten genau einen Fehler: `PreviewLinksTests.testAnchorsStayInOfflineDocument`. Foundation liefert für die opaque URL `about:blank#section` unter macOS 15 einen anderen `path` als lokal. Der Ankercheck prüft nun die exakte serialisierte Offline-Dokumentadresse mit Fragmenttrenner. Query-, Host- und andere Pfadvarianten bleiben blockiert; zusätzliche Grenzfälle sind getestet. Kein Test übersprungen.

Produktversion auf 0.1.1 (Build 2) erhöht; v0.1.0 und dessen Asset bleiben unverändert. Vor Veröffentlichung von 0.1.1 wird zusätzlich zum lokalen Gate der CI-Erfolg des Quellcommits abgewartet.

Diagnose nach dem zweiten CI-Fehler: Der Runner serialisiert `URL(string: "about:blank#section")` tatsächlich als `about:blank%23section`, mit leerem path und ohne fragment (Lauf 36320292740). Der Test baut die WebKit-URL deshalb nun aus ihrer unveränderten Datenrepräsentation und prüft zusätzlich die bytegetreue absoluteString-Darstellung. Prozentkodierte Trenner bleiben ausdrücklich ausgeschlossen. Der Produktionscheck bleibt auf echte `about:blank#`-Adressen begrenzt. Die neue CI-Sperre hat die verfrühte Veröffentlichung von 0.1.1 im Dry-run nachweislich verhindert.

## Endgültige Behebung: hierarchische Offline-Adresse

Auch Daten- und CoreFoundation-Konstruktoren kodieren auf dem macOS-15-Runner den Trenner beim Swift-URL-Übergang um. Statt weiterer Konstruktorvarianten verwendet die Vorschau jetzt `https://textui-preview.invalid/` als interne Basisadresse für `loadHTMLString`. Die reservierte .invalid-Adresse dient nur als Dokumentbasis; HTML wird direkt übergeben und die CSP blockiert Netzwerkzugriff. Echte Fragmente werden anhand von Schema, Host, Pfad, fehlenden Zugangsdaten/Port/Query und vorhandenem Fragment geprüft. Andere Ziele bleiben blockiert bzw. echte Weblinks bestätigungspflichtig. Ein neuer WKWebView-Test prüft die tatsächlich geladene Dokumentadresse und aufgelöste Ankeradresse unter derselben Offline-CSP und mit abgeschalteten Dokumentskripten. Die About-Anzeige übernimmt die Version jetzt aus dem Bundle statt aus einem festen 0.1.0-Text.

## Offener Abschluss nach Hinweis auf GitHub-Fehlermails

Die abschließende lokale Änderung mit hierarchischer .invalid-Vorschauadresse besteht alle 49 Tests (41 Core, 8 native Tests einschließlich realer WebView/Ankerauflösung); `git diff --check` bestanden. Diese Änderung ist noch NICHT committed oder gepusht. GitHub-CI-Erfolg ist dafür noch nicht belegt.

Der Nutzer meldete die vielen CI-Fehlermails. Die automatische Freigabeprüfung blockierte daraufhin Commit/Push der fertigen Korrektur, weil dadurch ein weiterer CI-Lauf mit möglichen Benachrichtigungen ausgelöst würde; erneute Nutzerzustimmung ist erforderlich. Kein Umgehen der Sperre. Öffentlicher main-Stand beim Stopp: `972be953999137cf30227d21162182285b139e88`; letzter CI-Lauf 36320551905 fehlgeschlagen. Öffentlicher Release bleibt v0.1.0. Die vorhandenen lokalen 0.1.1-Artefakte stammen von früheren Quellständen und dürfen NICHT als fertige Korrektur veröffentlicht werden.

Nach Zustimmung: lokale Korrektur committen/pushen, exakt diesen CI-Lauf erfolgreich abwarten, älteren unveröffentlichten 0.1.1-Ausgabeordner erhalten/verschieben, finalen sauberen Quellcommit über release.sh neu bauen/signieren/notarisieren, publish --dry-run und Veröffentlichung samt Downloadprüfung ausführen. Release-Tag 0.1.0 nicht verändern. Abschließend die exakten 0.1.1-Nachweise dokumentieren und sauberen synchronen Git-Stand prüfen.

## Fortsetzung freigegeben

Der Nutzer hat den Push der neuen Version einschließlich weiterem CI-Lauf und Veröffentlichung von 0.1.1 ausdrücklich bestätigt. Die vorstehende Freigabesperre ist damit aufgehoben. Der bereits lokal mit 49 erfolgreichen Tests geprüfte Stand wird committed und gepusht; Veröffentlichung erfolgt erst nach erfolgreicher CI-Prüfung desselben Commits.

## Abgeschlossen: öffentlicher Release 0.1.1

- Release: https://github.com/r3d42-git/R3DsTextUI/releases/tag/v0.1.1 ; öffentlich, kein Draft/Prerelease.
- Unveränderlicher Tag `v0.1.1` auf Quellcommit `6b3cd5c7ca9d2ab03d969cdd57ac93e3332ff1f9`. Der nachfolgende Dokumentationscommit verändert weder Tag noch Artefakt.
- Erfolgreiche CI des exakten Releasecommits: https://github.com/r3d42-git/R3DsTextUI/actions/runs/36320863042 . Alle Tests, App-Bundlebuild und arm64-Prüfung unter macOS 15 bestanden. Die früheren fehlgeschlagenen Läufe bleiben historische Diagnoseergebnisse.
- Lokal 49 Tests bestanden (41 Core, 8 native Editor-/Vorschautests einschließlich echter WebView mit hierarchischer Offline-Basisadresse).
- Asset: https://github.com/r3d42-git/R3DsTextUI/releases/download/v0.1.1/TextUI-0.1.1-macOS-arm64.zip ; SHA-256-Datei daneben.
- ZIP SHA-256: `832296816f3c115221af0b4bace85d063fc4c8551c25dd86c1458269bbb2725e`.
- Apple-Submission `90e45102-c51e-4b88-8239-b2fdd880ee9b`: `Accepted`. Developer ID Application: Philipp John Hild, Team `G6JH37W285`, Hardened Runtime, Zeitstempel und vor der ZIP-Erstellung angeheftetes App-Ticket.
- Version 0.1.1 (Build 2), arm64, macOS 15+, Bundle-ID `com.r3d42.textui`, GPL-3.0-or-later.
- Publish-Dry-run bestanden. Frisch heruntergeladenes GitHub-ZIP stimmt mit lokaler Prüfsumme und GitHub-Digest überein; ZIP-Integrität, strict codesign, Identität/Version/Architektur/Lizenzdateien, stapler validate und Gatekeeper erfolgreich. Gatekeeper meldet `Notarized Developer ID`.
- Die ältere Version 0.1.0 wurde weder verändert noch entfernt. Ältere unveröffentlichte 0.1.1-Builds liegen getrennt unter dem ignorierten `.local/`; nur `dist/release/0.1.1` gehört zum finalen Releasecommit.
- Grenzen: kein Start auf einem sauberen fremden Mac, kein manueller vollständiger macOS-15-App-Abnahmetest und kein echter Rechnerneustart. CI-Tests unter macOS 15 sind davon getrennte Evidenz.
- Diese abschließende Dokumentation wird separat mit `[skip ci]` committed, um für reine Nachweise keinen weiteren identischen Build auszulösen. Der Releasecommit bleibt durch den erfolgreichen CI-Lauf belegt.

## JSON-Unterstützung – 2026-09-28

`.json` (auch Großschreibung) wird als JSON erkannt, im Öffnen-Dialog angeboten und als bearbeitbarer Dateityp im Bundle registriert. Syntaxfarben unterscheiden Schlüssel, Strings, Zahlen, Boolesche Werte/null und Interpunktion. Bestehende Speicher-, Kodierungs-, Konflikt- und Entwurfsregeln gelten unverändert; auch unvollständiges JSON lässt sich speichern.

Die Vorschau (⌥⌘P) validiert JSON und rückt es lesbar ein, ohne den Editorinhalt zu verändern. Der lexikalische Formatter erhält Schlüsselreihenfolge, doppelte Schlüssel, große Zahlen, Exponentenschreibweisen und String-Escapes. HTML in Strings wird escaped; bestehende Offline-CSP und Codekopie bleiben aktiv. Fehler erscheinen mit Zeile/Spalte statt einer veralteten Vorschau. Vorschautiefe auf 256 Ebenen begrenzt; keine JSONC-Kommentare oder nachgestellten Kommas.

Validierung: `swift test --arch arm64` mit 55 bestandenen Tests (47 Core, 8 native); sechs neue JSON-Tests prüfen Formatierung, ungültige Eingaben, Unicode/UTF-16-Tokenpositionen, HTML-Escaping, Präzision und Öffnen/Bearbeiten/Speichern/Session-Roundtrip mit UTF-16-BOM/CRLF. Lokales arm64-Bundle gebaut, plist und Ad-hoc-Signatur geprüft. Reale App: JSON über Öffnen-Dialog geladen, Syntaxfarben/formatierte Vorschau einschließlich großer Zahl und literalem HTML sichtbar geprüft; eingefügtes Komma erzeugt Fehlermeldung, Änderung rückgängig gemacht und Testtab geschlossen. Bestehende Nutzertabs erhalten. Laufende App ist `dist/TextUI.app`; `/Applications/TextUI.app` wurde nicht ersetzt. Keine Veröffentlichung oder neue Release-Version.

Nutzerabnahme am 2026-09-28: „funktioniert“. Anschließend vollständige Veröffentlichung inklusive Doku und Archify beauftragt. Die erste JSON-Implementierung oben beschreibt den Stand vor dieser Releasevorbereitung.

## Abgeschlossen: öffentlicher Release 0.1.2 – 2026-09-28

- Nutzerauftrag: vollständiger Weg von Commit/Push bis Release samt Beschreibung, Doku und Archify. JSON-Funktion zuvor vom Nutzer bestätigt.
- Implementierungscommit: `4a90c64e67d5fc52b7861e375b01907dca56f409`; darauf sind die zwölf Quellverweise der Archify-Seite festgesetzt.
- Unveränderlicher Tag `v0.1.2` auf Releasecommit `084765d6cd1dfcbaa2ad7184afcf43345fd68230` einschließlich der geprüften Archify-Dokumentation.
- Release: https://github.com/r3d42-git/R3DsTextUI/releases/tag/v0.1.2 ; öffentlich, kein Draft/Prerelease.
- Asset: https://github.com/r3d42-git/R3DsTextUI/releases/download/v0.1.2/TextUI-0.1.2-macOS-arm64.zip ; SHA-256-Datei daneben.
- ZIP SHA-256: `3316df5f507d7147312bccfca1d2e8aad3d4f024ed7ab81dc9cf683f598f9b81`.
- Version 0.1.2, Build 3, arm64, macOS 15+, Bundle-ID `com.r3d42.textui`, GPL-3.0-or-later.
- Erfolgreiche CI des exakten Releasecommits vor Veröffentlichung: https://github.com/r3d42-git/R3DsTextUI/actions/runs/36449061063 . Tests, App-Bundlebuild und arm64-Prüfung unter macOS 15 bestanden. Lokal alle 55 Tests (47 Core, 8 native) im Releaseablauf erneut bestanden.
- Apple-Submission `debd8cfa-130d-4475-8de6-b24de6806f16`: `Accepted`. Developer ID Application: Philipp John Hild, Team `G6JH37W285`, Hardened Runtime, sicherer Zeitstempel und vor der finalen ZIP-Erstellung angeheftetes App-Ticket.
- Publish-Dry-run bestanden. Frischer GitHub-Download stimmt mit lokaler Prüfsumme und GitHub-Asset-Digest überein. ZIP-Integrität, strict codesign, Identität/Version/Architektur/Lizenzdateien, stapler validate und Gatekeeper erfolgreich. Gatekeeper: `Notarized Developer ID`.
- GitHub-Projektbeschreibung nennt jetzt JSON. Deutsche/englische README, Release Notes und Bundle-Dateitypen aktualisiert.
- Archify: https://r3d42-git.github.io/R3DsTextUI/ ; Pages-Lauf https://github.com/r3d42-git/R3DsTextUI/actions/runs/36449061091 erfolgreich. Öffentlich abgerufenes HTML ist bytegleich mit dem geprüften lokalen Artefakt.
- Architektur-Spezifikation SHA-256: `15bccc5f2242fc273815a0ef83b88e4e98f3a8e7724a241536c16941f9e1d4af`; HTML SHA-256: `e6c8f01259f81502c1e6a453ebb778b375235230d92d42e34ac032801434ded1`. Archify: 9/9 Showcase, 0 Fehler/Warnungen, Browsernachweise bestanden bei 1440×900, 1600×1000, 1920×1080 und 2048×1320; helle/dunkle Screenshots visuell geprüft. Keine Geometriekorrekturen in dieser Aktualisierung. Receipts unter `docs/diagrams/delivery.json` und `docs/index.visual-check.json`.
- Grenzen: kein Start auf sauberem fremden Mac, kein vollständiger manueller macOS-15-Abnahmetest, kein Rechnerneustart. `/Applications/TextUI.app` wurde nicht ersetzt. Bestehende Nutzersitzung und ältere Releases bleiben erhalten.
- Dieser Nachweis wird als separater Dokumentationscommit mit `[skip ci]` nachgeführt; der veröffentlichte Tag bleibt unverändert.
