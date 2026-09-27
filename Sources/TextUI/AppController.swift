import AppKit
import UniformTypeIdentifiers
import WebKit
import TextUICore

final class DocumentTab {
    var draft: Draft
    let editor: EditorPane
    init(_ draft: Draft, fontSize: CGFloat) {
        self.draft = draft
        self.editor = EditorPane(text: draft.file.text, format: draft.format, fontSize: fontSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSSearchFieldDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var tabs: [DocumentTab] = []
    var selectedID: UUID?
    var current: DocumentTab? { tabs.first { $0.draft.id == selectedID } }
    var store = SessionStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.r3d42.textui/Session.json"))
    var sessionHealthy = true
    var ready = false
    var pendingURLs: [URL] = []
    var fileDecisionDepth = 0
    var checkpoint: DispatchWorkItem?
    var refresh: DispatchWorkItem?
    var fontSize: CGFloat = 14
    var wrap = true
    var autosave = false
    let tabStrip = NSStackView()
    let editorHost = NSView()
    let status = NSTextField(labelWithString: "")
    let sizeLabel = NSTextField(labelWithString: "14 pt")
    let outline = NSPopUpButton()
    let searchRow = NSStackView()
    let query = NSSearchField()
    let replacement = NSTextField()
    let matchCase = NSButton(checkboxWithTitle: "Aa", target: nil, action: nil)
    let wholeWord = NSButton(checkboxWithTitle: "Wort", target: nil, action: nil)
    let regex = NSButton(checkboxWithTitle: ".*", target: nil, action: nil)
    let matchCount = NSTextField(labelWithString: "")
    let split = NSStackView()
    let previewHost = NSView()
    var previewMinimumWidth: NSLayoutConstraint!
    let previewButton = NSButton()
    let previewNote = NSTextField(labelWithString: "Offline-Vorschau")
    private let previewQueue = DispatchQueue(label: "TextUI.preview", qos: .userInitiated)
    private var previewWork: DispatchWorkItem?
    private var previewGeneration = 0
    private var previewTabID: UUID?
    var webView: WKWebView!
    private var previewCodeCopy: PreviewCodeCopy?
    private var linkConfirmationVisible = false
    var previewVisible = false
    var searchRanges: [NSRange] = []
    var outlineEntries: [OutlineEntry] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        fontSize = CGFloat(UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 14)
        wrap = UserDefaults.standard.object(forKey: "wrap") as? Bool ?? true
        autosave = UserDefaults.standard.bool(forKey: "autosave")
        buildMenus()
        buildWindow()
        do {
            if let session = try store.load() {
                for var draft in session.drafts {
                    if !draft.isDirty, let url = draft.url, let fresh = try? Draft.open(url) {
                        draft.file = fresh.file; draft.baseline = fresh.baseline
                    }
                    add(draft, select: false)
                }
                selectedID = session.selected
            }
        } catch {
            let backup = store.url.deletingLastPathComponent().appendingPathComponent("Session-unreadable-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: store.url, to: backup)
                showMessage("Sitzung konnte nicht geladen werden", "Die ursprüngliche Sitzung bleibt als \(backup.lastPathComponent) im Anwendungsordner erhalten. TextUI beginnt eine neue Sitzung.")
            } catch {
                sessionHealthy = false
                showError(EditorError.invalidSession)
            }
        }
        if tabs.isEmpty { add(Draft(), select: false) }
        select(selectedID ?? tabs[0].draft.id)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        ready = true
        if !pendingURLs.isEmpty { let urls = pendingURLs; pendingURLs = []; open(urls) }
    }

    func buildMenus() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title); item.submenu = submenu; main.addItem(item); return submenu
        }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            menu.addItem(item)
        }
        let app = menu("TextUI")
        item(app, "Über TextUI", #selector(about))
        item(app, "Einstellungen …", #selector(showSettings), ",")
        app.addItem(.separator())
        item(app, "TextUI ausblenden", #selector(NSApplication.hide(_:)), "h")
        app.addItem(.separator())
        item(app, "TextUI beenden", #selector(NSApplication.terminate(_:)), "q")
        let file = menu("Ablage")
        item(file, "Neu", #selector(newDocument), "n")
        item(file, "Öffnen …", #selector(openDocument), "o")
        item(file, "Speichern", #selector(saveDocument), "s")
        item(file, "Speichern unter …", #selector(saveAs), "s", [.command, .shift])
        file.addItem(.separator())
        item(file, "Tab schließen", #selector(closeCurrentTab), "w")
        item(file, "Fenster schließen · Entwürfe behalten", #selector(closeWindow), "w", [.command, .shift])
        item(file, "Automatisch speichern", #selector(toggleAutosave))
        let edit = menu("Bearbeiten")
        item(edit, "Rückgängig", Selector(("undo:")), "z")
        item(edit, "Wiederholen", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        item(edit, "Ausschneiden", #selector(NSText.cut(_:)), "x")
        item(edit, "Kopieren", #selector(NSText.copy(_:)), "c")
        item(edit, "Einsetzen", #selector(NSText.paste(_:)), "v")
        item(edit, "Alles auswählen", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        item(edit, "Suchen und Ersetzen …", #selector(showSearch), "f")
        item(edit, "Nächster Treffer", #selector(nextMatch), "g")
        item(edit, "Vorheriger Treffer", #selector(previousMatch), "g", [.command, .shift])
        let view = menu("Darstellung")
        item(view, "Schriftgröße …", #selector(showSettings))
        item(view, "Zeilenumbruch", #selector(toggleWrap))
        item(view, "Vorschau", #selector(togglePreview), "p", [.command, .option])
        let navigation = menu("Navigation")
        item(navigation, "Gehe zu Zeile …", #selector(goToLine), "l")
        item(navigation, "Nächster Tab", #selector(nextTab), "]", [.command, .shift])
        item(navigation, "Vorheriger Tab", #selector(previousTab), "[", [.command, .shift])
        item(navigation, "Tab nach links verschieben", #selector(moveTabLeft))
        item(navigation, "Tab nach rechts verschieben", #selector(moveTabRight))
        NSApp.mainMenu = main
        for submenu in main.items.compactMap(\.submenu) {
            for entry in submenu.items where entry.action != nil {
                if responds(to: entry.action!) { entry.target = self }
            }
        }
    }

    func button(_ title: String, _ action: Selector, symbol: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        if let symbol { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); button.imagePosition = .imageLeading }
        return button
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "TextUI"
        window.minSize = NSSize(width: 840, height: 450)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("TextUI.Main")
        let root = NSStackView()
        root.orientation = .vertical; root.spacing = 0; root.alignment = .leading
        window.contentView = root
        let toolbar = NSStackView(views: [button("Neu", #selector(newDocument), symbol: "plus"), button("Öffnen", #selector(openDocument), symbol: "folder"), button("Speichern", #selector(saveDocument), symbol: "square.and.arrow.down")])
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(spacer)
        outline.target = self; outline.action = #selector(jumpOutline)
        outline.addItem(withTitle: "Gliederung")
        outline.widthAnchor.constraint(equalToConstant: 175).isActive = true
        outline.toolTip = "Überschriften im Dokument"
        toolbar.addArrangedSubview(outline)
        toolbar.addArrangedSubview(button("Suchen", #selector(showSearch), symbol: "magnifyingglass"))
        previewButton.title = "Vorschau"; previewButton.target = self; previewButton.action = #selector(togglePreview); previewButton.bezelStyle = .rounded
        previewButton.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Vorschau")
        previewButton.imagePosition = .imageLeading
        toolbar.addArrangedSubview(previewButton)
        root.addArrangedSubview(toolbar)
        let tabScroll = NSScrollView()
        tabScroll.hasHorizontalScroller = true; tabScroll.autohidesScrollers = true; tabScroll.drawsBackground = false
        tabStrip.orientation = .horizontal; tabStrip.spacing = 8
        tabStrip.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        tabScroll.documentView = tabStrip
        tabStrip.heightAnchor.constraint(equalTo: tabScroll.contentView.heightAnchor).isActive = true
        tabStrip.leadingAnchor.constraint(equalTo: tabScroll.contentView.leadingAnchor).isActive = true
        tabStrip.topAnchor.constraint(equalTo: tabScroll.contentView.topAnchor).isActive = true
        tabScroll.heightAnchor.constraint(equalToConstant: 43).isActive = true
        root.addArrangedSubview(tabScroll)
        configureSearch()
        root.addArrangedSubview(searchRow)
        split.orientation = .horizontal; split.distribution = .fillEqually
        split.alignment = .height; split.spacing = 1
        split.detachesHiddenViews = true
        editorHost.clipsToBounds = true
        split.addArrangedSubview(editorHost)
        editorHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        previewCodeCopy = PreviewCodeCopy(configuration: config)
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        previewNote.font = .systemFont(ofSize: 11)
        previewNote.textColor = .secondaryLabelColor
        previewNote.toolTip = "Ohne Skripte, externe Inhalte und lokale Bild-/CSS-Dateien"
        previewNote.lineBreakMode = .byTruncatingTail
        previewNote.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let previewStack = NSStackView(views: [previewNote, webView])
        previewStack.orientation = .vertical; previewStack.alignment = .leading; previewStack.spacing = 8
        pin(previewStack, in: previewHost, inset: 10)
        webView.widthAnchor.constraint(equalTo: previewStack.widthAnchor).isActive = true
        split.addArrangedSubview(previewHost)
        previewMinimumWidth = previewHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 240)
        previewHost.isHidden = true
        root.addArrangedSubview(split)
        let bottom = NSStackView()
        bottom.spacing = 10; bottom.edgeInsets = NSEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        bottom.addArrangedSubview(status)
        let filler = NSView(); filler.setContentHuggingPriority(.defaultLow, for: .horizontal); bottom.addArrangedSubview(filler)
        bottom.addArrangedSubview(button("Umbruch", #selector(toggleWrap)))
        bottom.addArrangedSubview(button("Schrift …", #selector(showSettings)))
        bottom.addArrangedSubview(sizeLabel)
        root.addArrangedSubview(bottom)
        for view in root.arrangedSubviews { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        split.setContentHuggingPriority(.defaultLow, for: .vertical)
        split.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    func pin(_ child: NSView, in parent: NSView, inset: CGFloat = 0) {
        parent.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset), child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset), child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset), child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)])
    }

    func configureSearch() {
        searchRow.orientation = .horizontal; searchRow.spacing = 6
        searchRow.edgeInsets = NSEdgeInsets(top: 6, left: 14, bottom: 8, right: 14)
        query.placeholderString = "Im Dokument suchen"; query.delegate = self
        query.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        replacement.placeholderString = "Ersetzen durch"; replacement.delegate = self
        replacement.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        for check in [matchCase, wholeWord, regex] { check.target = self; check.action = #selector(searchChanged) }
        matchCase.toolTip = "Groß-/Kleinschreibung beachten"; regex.toolTip = "Regulärer Ausdruck (Ersetzung als wörtlicher Text)"
        for view in [query, matchCase, wholeWord, regex, button("↑", #selector(previousMatch)), button("↓", #selector(nextMatch)), matchCount, replacement, button("Ersetzen", #selector(replaceOne)), button("Alle", #selector(replaceAll)), button("×", #selector(hideSearch))] { searchRow.addArrangedSubview(view) }
        searchRow.isHidden = true
    }

    func add(_ draft: Draft, select shouldSelect: Bool = true) {
        let tab = DocumentTab(draft, fontSize: fontSize)
        tab.editor.onChange = { [weak self, weak tab] in
            guard let self, let tab else { return }
            tab.draft.file.text = tab.editor.textView.string
            self.changed(tab)
        }
        tab.editor.onSelection = { [weak self] in self?.updateStatus(); if self?.ready == true { self?.persistSoon() } }
        tabs.append(tab)
        if shouldSelect { select(draft.id); persistSoon() }
    }

    func capture() {
        for tab in tabs {
            tab.draft.file.text = tab.editor.textView.string
            if tab.editor.view.superview != nil {
                tab.draft.selection = tab.editor.textView.selectedRange().location
                tab.draft.scrollY = tab.editor.scrollView.contentView.bounds.origin.y
            }
        }
    }

    func select(_ id: UUID) {
        capture()
        selectedID = tabs.contains(where: { $0.draft.id == id }) ? id : tabs.first?.draft.id
        editorHost.subviews.forEach { $0.removeFromSuperview() }
        guard let tab = current else { return }
        pin(tab.editor.view, in: editorHost)
        updatePreview()
        window.contentView?.layoutSubtreeIfNeeded()
        tab.editor.updateAppearance(format: tab.draft.format, fontSize: fontSize, wrap: wrap)
        tab.editor.finishLayout()
        tab.editor.textView.setSelectedRange(NSRange(location: min(tab.draft.selection, (tab.editor.textView.string as NSString).length), length: 0))
        window.makeFirstResponder(tab.editor.textView)
        tab.editor.scrollView.contentView.scroll(to: NSPoint(x: 0, y: tab.draft.scrollY))
        tab.editor.scrollView.reflectScrolledClipView(tab.editor.scrollView.contentView)
        rebuildTabs(); updateStatus(); updateOutline(); updateSearch()
        let savedY = tab.draft.scrollY
        DispatchQueue.main.async { [weak self, weak tab] in
            guard let self, let tab, self.current === tab else { return }
            self.window.contentView?.layoutSubtreeIfNeeded()
            tab.editor.finishLayout()
            tab.editor.scrollView.contentView.scroll(to: NSPoint(x: 0, y: savedY))
            tab.editor.scrollView.reflectScrolledClipView(tab.editor.scrollView.contentView)
        }
    }

    func rebuildTabs() {
        tabStrip.arrangedSubviews.forEach { tabStrip.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (index, tab) in tabs.enumerated() {
            let title = (tab.draft.isDirty ? "● " : "") + tab.draft.title
            let selectButton = button(title, #selector(tabClicked(_:)))
            selectButton.isBordered = false
            selectButton.tag = index
            selectButton.toolTip = tab.draft.url?.path ?? "Noch nicht als Datei gespeichert"
            selectButton.contentTintColor = tab.draft.id == selectedID ? .labelColor : .secondaryLabelColor
            selectButton.font = .systemFont(ofSize: 12, weight: tab.draft.id == selectedID ? .semibold : .regular)
            let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Tab schließen")!, target: self, action: #selector(tabCloseClicked(_:)))
            close.tag = index; close.isBordered = false; close.toolTip = "Tab schließen"
            let group = NSStackView(views: [selectButton, close]); group.spacing = 8
            group.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
            tabStrip.addArrangedSubview(group)
        }
        window.title = "\(current?.draft.title ?? "TextUI") — TextUI"
    }

    func changed(_ tab: DocumentTab) {
        previewGeneration += 1
        previewWork?.cancel()
        rebuildTabs(); updateStatus(); persistSoon()
        refresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let tab = self.current {
                tab.editor.updateAppearance(format: tab.draft.format, fontSize: self.fontSize, wrap: self.wrap)
            }
            self.updateSearch(); self.updateOutline(); self.updatePreview()
            if self.autosave && self.fileDecisionDepth == 0 {
                for pending in self.tabs where pending.draft.url != nil && pending.draft.isDirty {
                    if !self.save(pending, saveAs: false) { self.autosave = false; UserDefaults.standard.set(false, forKey: "autosave"); self.updateStatus(); break }
                }
            }
        }
        refresh = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: work)
    }

    func persistSoon() {
        checkpoint?.cancel()
        let work = DispatchWorkItem { [weak self] in _ = self?.persist() }
        checkpoint = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    @discardableResult func persist() -> Bool {
        guard sessionHealthy else { return false }
        capture()
        do { try store.save(Session(drafts: tabs.map(\.draft), selected: selectedID)); return true }
        catch { showError(error); return false }
    }

    func updateStatus() {
        guard let tab = current else { return }
        let selection = tab.editor.textView.selectedRange()
        let position = TextNavigation.position(tab.editor.textView.string, at: selection.location)
        let count = selection.length > 0 ? " · \((tab.editor.textView.string as NSString).substring(with: selection).count) ausgewählt" : ""
        status.stringValue = "Z \(position.line) : S \(position.column)\(count)   ·   \(tab.draft.format.rawValue)   ·   \(tab.draft.file.encodingName) / \(tab.draft.file.lineEnding)\(autosave ? "   ·   Auto" : "")"
        sizeLabel.stringValue = "\(Int(fontSize)) pt"
    }

    @objc func newDocument() { add(Draft()); window.makeKeyAndOrderFront(nil) }
    @objc func openDocument() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .html, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK { open(panel.urls) }
    }
    func open(_ urls: [URL]) {
        for url in urls {
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            if let existing = tabs.first(where: { $0.draft.url == resolved }) { select(existing.draft.id); continue }
            do { add(try Draft.open(resolved)) } catch { showError(error) }
        }
        window.makeKeyAndOrderFront(nil)
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if ready { open(urls) } else { pendingURLs.append(contentsOf: urls) }
        sender.reply(toOpenOrPrint: .success)
    }
    @objc func saveDocument() { if let current { _ = save(current, saveAs: false) } }
    @objc func saveAs() { if let current { _ = save(current, saveAs: true) } }
    @discardableResult func save(_ tab: DocumentTab, saveAs: Bool) -> Bool {
        fileDecisionDepth += 1
        defer { fileDecisionDepth -= 1 }
        var destination = tab.draft.url
        if saveAs || destination == nil {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = tab.draft.url?.lastPathComponent ?? "Unbenannt.txt"
            panel.directoryURL = tab.draft.url?.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            destination = url
        }
        guard let destination else { return false }
        let resolved = destination.standardizedFileURL.resolvingSymlinksInPath()
        if tabs.contains(where: { $0 !== tab && $0.draft.url == resolved }) {
            showMessage("Datei bereits geöffnet", "Diese Datei ist in einem anderen Tab geöffnet. Wähle einen anderen Namen.")
            return false
        }
        tab.draft.file.text = tab.editor.textView.string
        do {
            try tab.draft.save(to: resolved)
            tab.editor.updateAppearance(format: tab.draft.format, fontSize: fontSize, wrap: wrap)
            rebuildTabs(); updateStatus(); updateOutline(); updatePreview()
            return persist()
        } catch { showError(error); return false }
    }

    @objc func tabClicked(_ sender: NSButton) { select(tabs[sender.tag].draft.id); persistSoon() }
    @objc func tabCloseClicked(_ sender: NSButton) { closeTab(tabs[sender.tag]) }
    @objc func closeCurrentTab() { if let current { closeTab(current) } }
    func closeTab(_ tab: DocumentTab) {
        refresh?.cancel()
        fileDecisionDepth += 1
        defer { fileDecisionDepth -= 1; if autosave, let current { changed(current) } }
        if tab.draft.isDirty {
            let alert = NSAlert()
            alert.messageText = "Änderungen an „\(tab.draft.title)“ speichern?"
            alert.informativeText = "Beim Verwerfen wird auch der gesicherte Entwurf dieses Tabs entfernt."
            alert.addButton(withTitle: "Speichern"); alert.addButton(withTitle: "Verwerfen"); alert.addButton(withTitle: "Abbrechen")
            alert.buttons[2].keyEquivalent = "\u{1b}"
            switch alert.runModal() {
            case .alertFirstButtonReturn: guard save(tab, saveAs: false) else { return }
            case .alertSecondButtonReturn: break
            default: return
            }
        }
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let oldTabs = tabs, oldSelection = selectedID
        tabs.remove(at: index)
        if selectedID == tab.draft.id { selectedID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].draft.id }
        if !persist() { tabs = oldTabs; selectedID = oldSelection; return }
        if tabs.isEmpty { add(Draft()) } else { select(selectedID ?? tabs[0].draft.id) }
    }
    @objc func closeWindow() { window.performClose(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { persist() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { persist() ? .terminateNow : .terminateCancel }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }

    @objc func toggleAutosave() {
        autosave.toggle(); UserDefaults.standard.set(autosave, forKey: "autosave"); updateStatus()
        if autosave { for tab in tabs where tab.draft.url != nil && tab.draft.isDirty { if !save(tab, saveAs: false) { autosave = false; UserDefaults.standard.set(false, forKey: "autosave"); break } } }
    }
    @objc func nextTab() { switchTab(1) }
    @objc func previousTab() { switchTab(-1) }
    func switchTab(_ step: Int) { guard let index = tabs.firstIndex(where: { $0.draft.id == selectedID }), !tabs.isEmpty else { return }; select(tabs[(index + step + tabs.count) % tabs.count].draft.id); persistSoon() }
    @objc func moveTabLeft() { moveTab(-1) }
    @objc func moveTabRight() { moveTab(1) }
    func moveTab(_ step: Int) {
        guard let index = tabs.firstIndex(where: { $0.draft.id == selectedID }), tabs.indices.contains(index + step) else { return }
        tabs.swapAt(index, index + step); rebuildTabs(); persistSoon()
    }
    @objc func showSettings() {
        let sizes = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
        sizes.addItems(withTitles: (10...28).map { "\($0) pt" })
        sizes.selectItem(withTitle: "\(Int(fontSize)) pt")
        sizes.setAccessibilityLabel("Schriftgröße")
        let dialog = NSAlert()
        dialog.messageText = "Einstellungen"
        dialog.informativeText = "Schriftgröße für alle Dokumente. Die neue Größe wird erst mit „Übernehmen“ angewendet. Standard: 14 pt."
        dialog.accessoryView = sizes
        dialog.addButton(withTitle: "Übernehmen")
        dialog.addButton(withTitle: "Abbrechen")
        dialog.window.initialFirstResponder = sizes
        guard dialog.runModal() == .alertFirstButtonReturn else { return }
        let selectedSize = CGFloat(sizes.indexOfSelectedItem + 10)
        guard selectedSize != fontSize else { return }
        fontSize = selectedSize
        updateAppearance()
    }
    @objc func toggleWrap() { wrap.toggle(); updateAppearance() }
    func updateAppearance() {
        UserDefaults.standard.set(Double(fontSize), forKey: "fontSize"); UserDefaults.standard.set(wrap, forKey: "wrap")
        if let tab = current { tab.editor.updateAppearance(format: tab.draft.format, fontSize: fontSize, wrap: wrap) }
        updateStatus()
    }
    @objc func goToLine() {
        guard let tab = current else { return }
        let starts = TextNavigation.lineStarts(tab.editor.textView.string)
        let field = NSTextField(string: "1"); field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        let alert = NSAlert(); alert.messageText = "Gehe zu Zeile"; alert.informativeText = "Zeile 1 bis \(starts.count)"; alert.accessoryView = field
        alert.addButton(withTitle: "Gehe zu"); alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn, let line = Int(field.stringValue), (1...starts.count).contains(line) { jump(to: NSRange(location: starts[line - 1], length: 0)) }
    }
    func updateOutline() {
        outline.removeAllItems(); outline.addItem(withTitle: "Gliederung")
        guard let tab = current else { return }
        outlineEntries = TextNavigation.outline(tab.editor.textView.string, format: tab.draft.format)
        outline.addItems(withTitles: outlineEntries.map { String($0.title.prefix(70)) })
        outline.isEnabled = !outlineEntries.isEmpty
    }
    @objc func jumpOutline() { let index = outline.indexOfSelectedItem - 1; if outlineEntries.indices.contains(index) { jump(to: NSRange(location: outlineEntries[index].location, length: 0)) }; outline.selectItem(at: 0) }
    func jump(to range: NSRange) { guard let text = current?.editor.textView else { return }; text.setSelectedRange(range); text.scrollRangeToVisible(range); window.makeFirstResponder(text); updateStatus() }

    @objc func showSearch() { searchRow.isHidden = false; window.makeFirstResponder(query); updateSearch() }
    @objc func hideSearch() { searchRow.isHidden = true; window.makeFirstResponder(current?.editor.textView) }
    var searchOptions: SearchOptions { SearchOptions(caseSensitive: matchCase.state == .on, wholeWord: wholeWord.state == .on, regex: regex.state == .on) }
    func controlTextDidChange(_ obj: Notification) { if obj.object as? NSSearchField === query { updateSearch() } }
    @objc func searchChanged() { updateSearch() }
    func updateSearch() {
        do { searchRanges = try searchOptions.matches(in: current?.editor.textView.string ?? "", query: query.stringValue); matchCount.stringValue = "\(searchRanges.count) Treffer"; matchCount.textColor = .secondaryLabelColor }
        catch { searchRanges = []; matchCount.stringValue = "Muster ungültig"; matchCount.textColor = .systemRed }
    }
    @objc func nextMatch() { navigateSearch(forward: true) }
    @objc func previousMatch() { navigateSearch(forward: false) }
    func navigateSearch(forward: Bool) {
        updateSearch(); guard let text = current?.editor.textView, !searchRanges.isEmpty else { return }
        let selected = text.selectedRange()
        let exact = searchRanges.firstIndex(of: selected)
        let range: NSRange
        if let exact { range = searchRanges[(exact + (forward ? 1 : -1) + searchRanges.count) % searchRanges.count] }
        else if forward { range = searchRanges.first(where: { $0.location >= NSMaxRange(selected) }) ?? searchRanges[0] }
        else { range = searchRanges.last(where: { $0.location < selected.location }) ?? searchRanges.last! }
        jump(to: range)
    }
    @objc func replaceOne() {
        updateSearch(); guard let text = current?.editor.textView else { return }
        let range = text.selectedRange()
        guard searchRanges.contains(range) else { nextMatch(); return }
        if text.shouldChangeText(in: range, replacementString: replacement.stringValue) { text.textStorage?.replaceCharacters(in: range, with: replacement.stringValue); text.didChangeText(); text.setSelectedRange(NSRange(location: range.location + (replacement.stringValue as NSString).length, length: 0)); nextMatch() }
    }
    @objc func replaceAll() {
        updateSearch(); guard let text = current?.editor.textView, !searchRanges.isEmpty else { return }
        let ranges = searchRanges
        text.undoManager?.beginUndoGrouping()
        for range in ranges.reversed() {
            if text.shouldChangeText(in: range, replacementString: replacement.stringValue) { text.textStorage?.replaceCharacters(in: range, with: replacement.stringValue) }
        }
        text.didChangeText(); text.undoManager?.endUndoGrouping(); updateSearch()
    }

    @objc func togglePreview() { previewVisible.toggle(); updatePreview() }
    func updatePreview() {
        previewGeneration += 1
        previewWork?.cancel()
        let supported = current.map { $0.draft.format != .text } ?? false
        previewButton.isEnabled = supported
        previewButton.toolTip = supported ? "Vorschau ein-/ausblenden (⌥⌘P)" : "Vorschau für Markdown, HTML und erkannte DokuWiki-Texte verfügbar"
        previewHost.isHidden = !previewVisible || !supported
        previewMinimumWidth.isActive = !previewHost.isHidden
        split.layoutSubtreeIfNeeded()
        current?.editor.finishLayout()
        guard previewVisible, supported, let tab = current else {
            if previewTabID != nil {
                webView.stopLoading()
                webView.loadHTMLString("", baseURL: nil)
                previewTabID = nil
            }
            return
        }
        let text = tab.editor.textView.string
        let format = tab.draft.format
        let generation = previewGeneration
        previewNote.stringValue = "\(format.rawValue) · Offline-Vorschau"
        // Clear the previous tab immediately; an older parse must never appear
        // after a tab switch, edit, or closing the preview.
        if previewTabID != tab.draft.id {
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
            previewTabID = tab.draft.id
        }
        let work = DispatchWorkItem { [weak self] in
            let rendered: String
            switch format {
            case .markdown: rendered = MarkdownPreview.html(from: text)
            case .dokuwiki: rendered = DokuWikiPreview.html(from: text)
            case .html, .text: rendered = text
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.previewGeneration == generation, self.previewVisible else { return }
                let policy = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; form-action 'none'; base-uri 'none'; script-src 'none'\">"
                self.webView.loadHTMLString(policy + rendered, baseURL: PreviewLinks.documentURL)
            }
        }
        previewWork = work
        previewQueue.async(execute: work)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.navigationType == .other && (url.absoluteString == "about:blank" || url == PreviewLinks.documentURL) {
            decisionHandler(.allow)
            return
        }
        guard navigationAction.navigationType == .linkActivated, navigationAction.sourceFrame.isMainFrame else {
            decisionHandler(.cancel)
            return
        }
        if PreviewLinks.isDocumentAnchor(url) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        guard let destination = PreviewLinks.browserURL(url), !linkConfirmationVisible else { return }
        linkConfirmationVisible = true
        let alert = NSAlert()
        alert.messageText = "Link im Standardbrowser öffnen?"
        alert.informativeText = "Du verlässt die lokale Vorschau und öffnest diese Adresse:\n\n\(destination.absoluteString)"
        alert.addButton(withTitle: "Abbrechen")
        alert.addButton(withTitle: "Im Browser öffnen")
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.linkConfirmationVisible = false
            guard response == .alertSecondButtonReturn else { return }
            if !NSWorkspace.shared.open(destination) {
                self?.showMessage("Link konnte nicht geöffnet werden", destination.absoluteString)
            }
        }
    }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "TextUI", .applicationVersion: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Entwicklung"), .credits: NSAttributedString(string: "Ein schlanker, lokaler Texteditor für macOS.")]) }
    func showError(_ error: Error) { let alert = NSAlert(error: error); alert.runModal() }
    func showMessage(_ title: String, _ detail: String) { let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.runModal() }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAutosave) { menuItem.state = autosave ? .on : .off }
        if menuItem.action == #selector(toggleWrap) { menuItem.state = wrap ? .on : .off }
        if menuItem.action == #selector(togglePreview) { menuItem.state = previewVisible ? .on : .off; return current.map { $0.draft.format != .text } ?? false }
        return true
    }
}
