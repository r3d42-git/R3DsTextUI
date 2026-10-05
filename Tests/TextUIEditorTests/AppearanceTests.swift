import AppKit
import XCTest
import TextUICore
@testable import TextUI

final class AppearanceTests: XCTestCase {
    @MainActor
    func testAppAppearanceSwitchKeepsNativeWindowAndInactiveTabStable() async throws {
        _ = NSApplication.shared
        let previousAppearance = NSApp.appearance
        let suite = "TextUI.AppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let delegate = AppDelegate()
        let sessionDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        delegate.store = SessionStore(url: sessionDirectory.appendingPathComponent("Session.json"))
        delegate.appearanceDefaults = defaults
        delegate.buildWindow(restoreFrame: false)
        defer {
            delegate.window.close()
            NSApp.appearance = previousAppearance
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: sessionDirectory)
        }
        let activeSource = String(repeating: "Normale kurze Zeile mit Worten.\n", count: 1400)
        let inactiveSource = String(repeating: "Große inaktive synthetische Zeile.\n", count: 32_000)
        delegate.add(Draft(file: TextFile(text: activeSource)), select: false)
        for _ in 0..<5 {
            delegate.add(Draft(file: TextFile(text: "Kleine normale Notiz.\n")), select: false)
        }
        delegate.add(Draft(file: TextFile(text: inactiveSource)), select: false)
        delegate.select(delegate.tabs[0].draft.id)
        delegate.window.displayIfNeeded()
        try await Task.sleep(nanoseconds: 300_000_000)
        let active = delegate.tabs[0].editor
        let inactive = try XCTUnwrap(delegate.tabs.last).editor
        active.textView.setSelectedRange(NSRange(location: 100, length: 4))
        let clip = active.scrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: 240))
        active.scrollView.reflectScrolledClipView(clip)
        let selection = active.textView.selectedRange()
        let origin = clip.bounds.origin
        XCTAssertGreaterThan(origin.y, 0, "Regression must exercise a scrolled document")
        let inactiveFrame = inactive.textView.frame
        let root = try XCTUnwrap(delegate.window.contentView as? ChromeStackView)
        let refresh = root.onAppearanceChange
        var changingAppearance = false
        root.onAppearanceChange = {
            XCTAssertFalse(changingAppearance, "Theme refresh must run after AppKit appearance invalidation")
            refresh?()
        }
        var changes = 0
        active.onChange = { changes += 1 }
        inactive.onChange = { changes += 1 }
        for mode in Array(repeating: [AppearanceMode.light, .dark], count: 5).flatMap({ $0 }) + [.system] {
            let item = NSMenuItem()
            item.representedObject = mode.rawValue
            let start = ProcessInfo.processInfo.systemUptime
            changingAppearance = true
            delegate.changeAppearance(item)
            changingAppearance = false
            delegate.window.displayIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2, "Appearance switching must return promptly")
            if mode != .system {
                XCTAssertEqual(active.textView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), mode.appearance?.name)
                XCTAssertEqual(delegate.webView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), mode.appearance?.name)
            }
            XCTAssertNil(active.view.appearance, "Editors inherit the application appearance without nested overrides")
            XCTAssertNil(inactive.view.appearance, "Detached tabs must not receive appearance mutations")
            XCTAssertEqual(inactive.textView.frame, inactiveFrame)
            XCTAssertEqual(active.textView.selectedRange(), selection)
            XCTAssertEqual(clip.bounds.origin, origin)
            XCTAssertEqual(active.textView.string, activeSource)
            XCTAssertEqual(inactive.textView.string, inactiveSource)
            XCTAssertEqual(defaults.string(forKey: "appearanceMode"), mode.rawValue)
        }
        // A formerly inactive tab adopts the current palette upon attachment.
        delegate.select(delegate.tabs[1].draft.id)
        let previouslyInactive = delegate.tabs[1].editor
        for mode in [AppearanceMode.dark, .light] {
            let item = NSMenuItem()
            item.representedObject = mode.rawValue
            delegate.changeAppearance(item)
            delegate.window.displayIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertEqual(previouslyInactive.textView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), mode.appearance?.name)
            XCTAssertEqual(previouslyInactive.textView.string, "Kleine normale Notiz.\n")
        }
        XCTAssertEqual(changes, 0)
    }

    @MainActor
    func testChromeAppearanceCallbacksAreDeferredAndCoalesced() async throws {
        let chrome = ChromeStackView()
        var refreshes = 0
        chrome.onAppearanceChange = { refreshes += 1 }
        chrome.viewDidChangeEffectiveAppearance()
        chrome.viewDidChangeEffectiveAppearance()
        chrome.viewDidChangeEffectiveAppearance()
        XCTAssertEqual(refreshes, 0, "Callbacks must not run inside AppKit invalidation")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(refreshes, 1, "One main-loop refresh handles repeated invalidations")
    }

    @MainActor
    func testPreferenceMappingAndNestedMenuChecks() {
        _ = NSApplication.shared
        XCTAssertEqual(AppearanceMode(savedValue: nil), .system)
        XCTAssertEqual(AppearanceMode(savedValue: "obsolete"), .system)
        XCTAssertNil(AppearanceMode.system.appearance)
        XCTAssertEqual(AppearanceMode.light.appearance?.name, .aqua)
        XCTAssertEqual(AppearanceMode.dark.appearance?.name, .darkAqua)
        for mode in AppearanceMode.allCases {
            XCTAssertEqual(AppearanceMode(savedValue: mode.rawValue), mode)
        }
        let previousMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMenu }
        let delegate = AppDelegate()
        delegate.buildMenus()
        let submenu = NSApp.mainMenu?.item(withTitle: "Darstellung")?.submenu?
            .item(withTitle: "Erscheinungsbild")?.submenu
        XCTAssertEqual(submenu?.items.map(\.title), ["Hell", "Dunkel", "System"])
        for mode in AppearanceMode.allCases {
            delegate.appearanceMode = mode
            for entry in submenu?.items ?? [] {
                XCTAssertTrue(entry.target === delegate)
                XCTAssertTrue(delegate.validateMenuItem(entry))
                XCTAssertEqual(entry.state, entry.title == mode.title ? .on : .off)
            }
        }
    }

    @MainActor
    func testPaletteSwitchPreservesTextSelectionSyntaxAndScroll() async throws {
        _ = NSApplication.shared
        let pane = EditorPane(text: "<p>Hallo</p>\n" + String(repeating: "text\n", count: 100), format: .html, fontSize: 14)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        let previousAppearance = NSApp.appearance
        let window = NSWindow(contentRect: host.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close(); NSApp.appearance = previousAppearance }
        host.addSubview(pane.view)
        pane.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pane.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            pane.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            pane.view.topAnchor.constraint(equalTo: host.topAnchor),
            pane.view.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        host.layoutSubtreeIfNeeded()
        pane.finishLayout()
        // Complete this small document to verify TextKit owns its scrollable height.
        pane.textView.layoutManager?.ensureLayout(for: try XCTUnwrap(pane.textView.textContainer))
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertGreaterThan(pane.textView.frame.height, pane.scrollView.contentSize.height,
                             "TextKit must grow the document beyond the viewport without layout resetting its height")
        let source = pane.textView.string
        let selection = NSRange(location: 3, length: 2)
        pane.textView.setSelectedRange(selection)
        let origin = pane.scrollView.contentView.bounds.origin
        var changes = 0
        pane.onChange = { changes += 1 }
        let layout = try XCTUnwrap(pane.textView.layoutManager)
        let syntax = try XCTUnwrap(layout.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil) as? NSColor)
        // A second tokenizer pass would erase this marker.
        layout.addTemporaryAttribute(.foregroundColor, value: NSColor.magenta, forCharacterRange: NSRange(location: 2, length: 1))
        var backgrounds: [NSColor] = []
        var chromes: [NSColor] = []
        var syntaxColors: [NSColor] = []
        for mode in [AppearanceMode.light, .dark, .light] {
            NSApp.appearance = mode.appearance
            pane.refreshColors()
            pane.textView.effectiveAppearance.performAsCurrentDrawingAppearance {
                backgrounds.append(EditorTheme.background.usingColorSpace(.deviceRGB)!)
                chromes.append(EditorTheme.windowChrome.usingColorSpace(.deviceRGB)!)
                syntaxColors.append(syntax.usingColorSpace(.deviceRGB)!)
            }
            XCTAssertEqual(pane.textView.string, source)
            XCTAssertEqual(pane.textView.selectedRange(), selection)
            XCTAssertEqual(pane.scrollView.contentView.bounds.origin, origin)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(layout.temporaryAttribute(.foregroundColor, atCharacterIndex: 2, effectiveRange: nil) as? NSColor, .magenta)
        XCTAssertNotEqual(backgrounds[0], backgrounds[1])
        XCTAssertEqual(backgrounds[0], backgrounds[2])
        XCTAssertNotEqual(chromes[0], chromes[1])
        XCTAssertNotEqual(syntaxColors[0], syntaxColors[1])
        NSApp.appearance = nil
        XCTAssertNil(pane.view.appearance, "System follows the application without an editor override")
        withExtendedLifetime(host) {}
    }
}
