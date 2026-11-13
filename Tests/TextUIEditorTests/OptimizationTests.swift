import AppKit
import XCTest
import TextUICore
@testable import TextUI

@MainActor
final class OptimizationTests: XCTestCase {
    private func makeDelegate() -> (AppDelegate, URL) {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let delegate = AppDelegate()
        delegate.store = SessionStore(url: directory.appendingPathComponent("Session.json"))
        delegate.buildWindow(restoreFrame: false)
        return (delegate, directory)
    }
    private func clean(_ delegate: AppDelegate, _ directory: URL) {
        delegate.checkpoint?.cancel(); delegate.refresh?.cancel(); delegate.invalidateSearch()
        delegate.sessionWriter.flush()
        delegate.window.delegate = nil; delegate.window.close()
        try? FileManager.default.removeItem(at: directory)
    }
    private func waitForSearch(_ delegate: AppDelegate) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while delegate.matchCount.stringValue == "Suche läuft …", ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotEqual(delegate.matchCount.stringValue, "Suche läuft …")
    }

    func testRegexTimeoutLeavesMainThreadResponsiveAndDoesNotApplyPartialMatches() async throws {
        let (delegate, directory) = makeDelegate()
        defer { clean(delegate, directory) }
        delegate.add(Draft(file: TextFile(text: String(repeating: "a", count: 100) + "!")))
        delegate.regex.state = .on; delegate.query.stringValue = "(a+)+$"
        delegate.updateSearch()
        let heartbeat = expectation(description: "UI queue can process input while searching")
        DispatchQueue.main.async { heartbeat.fulfill() }
        await fulfillment(of: [heartbeat], timeout: 0.1)
        try await waitForSearch(delegate)
        XCTAssertEqual(delegate.matchCount.stringValue, "Suche zu aufwendig")
        XCTAssertTrue(delegate.searchRanges.isEmpty)
        delegate.query.stringValue = "!"; delegate.nextMatch()
        try await waitForSearch(delegate)
        XCTAssertEqual(delegate.current?.editor.textView.selectedRange(), NSRange(location: 100, length: 1))
    }

    func testNewQueryTabAndEditInvalidateOldSearchResults() async throws {
        let (delegate, directory) = makeDelegate()
        defer { clean(delegate, directory) }
        delegate.add(Draft(file: TextFile(text: String(repeating: "a", count: 100) + "!")))
        delegate.regex.state = .on; delegate.query.stringValue = "(a+)+$"; delegate.updateSearch()
        delegate.add(Draft(file: TextFile(text: "😀 cat cat")))
        delegate.regex.state = .off; delegate.query.stringValue = "cat"; delegate.nextMatch()
        try await waitForSearch(delegate)
        XCTAssertEqual(delegate.searchRanges, [NSRange(location: 3, length: 3), NSRange(location: 7, length: 3)])
        XCTAssertEqual(delegate.current?.editor.textView.selectedRange(), NSRange(location: 3, length: 3))
        delegate.query.stringValue = "😀"; delegate.updateSearch()
        delegate.query.stringValue = "absent"; delegate.updateSearch()
        try await waitForSearch(delegate)
        XCTAssertTrue(delegate.searchRanges.isEmpty)
        let text = try XCTUnwrap(delegate.current?.editor.textView)
        text.insertText("absent", replacementRange: NSRange(location: 0, length: 2))
        delegate.updateSearch()
        try await waitForSearch(delegate)
        XCTAssertEqual(delegate.searchRanges, [NSRange(location: 0, length: 6)])
        XCTAssertEqual(delegate.current?.draft.file.text, "absent cat cat")
    }

    func testAsyncReplacementIsLiteralAndUndoable() async throws {
        let (delegate, directory) = makeDelegate()
        defer { clean(delegate, directory) }
        delegate.add(Draft(file: TextFile(text: "😀 cat cat")))
        let text = try XCTUnwrap(delegate.current?.editor.textView)
        delegate.query.stringValue = "cat"; delegate.replacement.stringValue = "$1🐈"
        delegate.replaceAll()
        try await waitForSearch(delegate)
        XCTAssertEqual(text.string, "😀 $1🐈 $1🐈")
        text.undoManager?.undo()
        XCTAssertEqual(text.string, "😀 cat cat")
        delegate.nextMatch(); try await waitForSearch(delegate)
        delegate.replacement.stringValue = "dog"; delegate.replaceOne()
        try await waitForSearch(delegate)
        XCTAssertEqual(text.string, "😀 dog cat")
        XCTAssertEqual(text.selectedRange(), NSRange(location: 7, length: 3))
        text.undoManager?.undo()
        XCTAssertEqual(text.string, "😀 cat cat")
        text.undoManager?.redo()
        XCTAssertEqual(text.string, "😀 dog cat")
        delegate.query.stringValue = "cat"; delegate.replacement.stringValue = "fox"
        delegate.replaceAll()
        try await waitForSearch(delegate)
        XCTAssertEqual(text.string, "😀 dog fox")
    }

    func testPendingSearchCommandsKeepOrderAndRepeatedNavigation() async throws {
        let (delegate, directory) = makeDelegate()
        defer { clean(delegate, directory) }
        delegate.add(Draft(file: TextFile(text: "cat cat cat")))
        delegate.query.stringValue = "cat"
        delegate.nextMatch(); delegate.nextMatch(); delegate.nextMatch()
        try await waitForSearch(delegate)
        XCTAssertEqual(delegate.current?.editor.textView.selectedRange(), NSRange(location: 8, length: 3))
        delegate.query.stringValue = "at"; delegate.replacement.stringValue = "ow"
        delegate.replaceAll(); delegate.nextMatch()
        delegate.replacement.stringValue = "later field edit"
        try await waitForSearch(delegate)
        XCTAssertEqual(delegate.current?.editor.textView.string, "cow cow cow")
        XCTAssertTrue(delegate.searchRanges.isEmpty)
    }

    func testPendingReplacementIsCancelledByQueryTabOrTextChange() async throws {
        let (delegate, directory) = makeDelegate()
        defer { clean(delegate, directory) }
        let source = String(repeating: "a", count: 100) + "!"
        delegate.add(Draft(file: TextFile(text: source)))
        let original = try XCTUnwrap(delegate.current)
        delegate.regex.state = .on; delegate.query.stringValue = "a|(a+)+$"
        delegate.replacement.stringValue = "x"; delegate.replaceAll()
        delegate.query.stringValue = "!"; delegate.updateSearch()
        try await waitForSearch(delegate)
        XCTAssertEqual(original.editor.textView.string, source)
        delegate.query.stringValue = "a|(a+)+$"; delegate.replaceAll()
        delegate.add(Draft(file: TextFile(text: "other tab")))
        try await waitForSearch(delegate)
        XCTAssertEqual(original.editor.textView.string, source)
        XCTAssertEqual(delegate.current?.editor.textView.string, "other tab")
        delegate.select(original.draft.id)
        delegate.query.stringValue = "a|(a+)+$"; delegate.replaceAll()
        original.editor.textView.insertText("?", replacementRange: NSRange(location: 100, length: 1))
        delegate.query.stringValue = "?"; delegate.regex.state = .off; delegate.updateSearch()
        try await waitForSearch(delegate)
        XCTAssertEqual(original.editor.textView.string, String(repeating: "a", count: 100) + "?")
        XCTAssertEqual(delegate.searchRanges, [NSRange(location: 100, length: 1)])
    }

    func testStatusCachesFormatAndNewlinesUntilTextChanges() throws {
        let (delegate, directory) = makeDelegate()
        defer { clean(delegate, directory) }
        delegate.add(Draft(file: TextFile(text: "first\r\nsecond")))
        XCTAssertTrue(delegate.status.stringValue.contains("CRLF"))
        delegate.current?.editor.textView.setSelectedRange(NSRange(location: 7, length: 0))
        XCTAssertTrue(delegate.status.stringValue.contains("Z 2 : S 1"))
        let text = try XCTUnwrap(delegate.current?.editor.textView)
        text.insertText("one\ntwo", replacementRange: NSRange(location: 0, length: text.string.utf16.count))
        XCTAssertTrue(delegate.status.stringValue.contains("UTF-8 / LF"))
        text.insertText("a\u{2028}", replacementRange: NSRange(location: 0, length: text.string.utf16.count))
        text.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertTrue(delegate.status.stringValue.contains("Z 2 : S 1"))
    }

    func testNavigationCheckpointKeepsContentFileUnchangedAndCloseOrdersWrites() throws {
        let (delegate, directory) = makeDelegate()
        defer { clean(delegate, directory) }
        let source = "😀 first\nsecond"
        for _ in 0..<2 { delegate.add(Draft(file: TextFile(text: source), baseline: Data(source.utf8))) }
        delegate.persistInBackground(); delegate.sessionWriter.flush()
        let content = try Data(contentsOf: delegate.store.url)
        delegate.current?.editor.textView.setSelectedRange(NSRange(location: 9, length: 0))
        delegate.persistSoon(contentChanged: false)
        delegate.persistInBackground(); delegate.sessionWriter.flush()
        XCTAssertEqual(try Data(contentsOf: delegate.store.url), content)
        XCTAssertEqual(try delegate.store.load()?.drafts.last?.selection, 9)
        let removedID = try XCTUnwrap(delegate.current?.draft.id)
        delegate.persistSoon(); delegate.persistInBackground()
        delegate.closeCurrentTab()
        delegate.sessionWriter.flush()
        XCTAssertFalse(try XCTUnwrap(delegate.store.load()).drafts.contains { $0.id == removedID })
        XCTAssertEqual(delegate.tabs.count, 1)
    }

    func testActiveTabStaysVisibleOnSwitchAndEditIncludingLongNames() throws {
        let (delegate, directory) = makeDelegate()
        defer { clean(delegate, directory) }
        delegate.window.setContentSize(NSSize(width: 840, height: 600))
        for index in 1...25 {
            let url = directory.appendingPathComponent("Konfiguration_Produktionsumgebung_Europa_final_version_\(index).xml")
            delegate.add(Draft(url: url, file: TextFile(text: "<root/>")), select: false)
        }
        delegate.select(delegate.tabs[0].draft.id)
        delegate.previousTab()
        func checkVisible() {
            let group = delegate.tabStrip.arrangedSubviews[24]
            let visible = delegate.tabStrip.visibleRect
            XCTAssertLessThanOrEqual(group.frame.maxX, visible.maxX + 1)
            XCTAssertGreaterThanOrEqual(group.frame.minX, visible.minX - 1)
            XCTAssertLessThanOrEqual(group.frame.width, 300)
            XCTAssertGreaterThanOrEqual(group.frame.minY, visible.minY - 1)
            XCTAssertLessThanOrEqual(group.frame.maxY, visible.maxY + 1)
        }
        checkVisible()
        delegate.current?.editor.textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
        checkVisible()
        XCTAssertEqual(delegate.selectedID, delegate.tabs[24].draft.id)
    }

    func testNativeSplitResizesDragsAndRestoresWithLargeFont() throws {
        let (delegate, directory) = makeDelegate()
        defer { clean(delegate, directory) }
        delegate.add(Draft(url: directory.appendingPathComponent("example.md"), file: TextFile(text: "# Long document title")))
        delegate.window.setContentSize(NSSize(width: 840, height: 600))
        delegate.fontSize = 28
        delegate.current?.editor.updateAppearance(format: .markdown, fontSize: 28, wrap: true)
        delegate.togglePreview()
        delegate.window.contentView?.layoutSubtreeIfNeeded()
        delegate.current?.editor.finishLayout()
        XCTAssertGreaterThan(delegate.split.bounds.height, 200)
        XCTAssertGreaterThanOrEqual(delegate.editorHost.frame.width, 480)
        XCTAssertGreaterThanOrEqual(delegate.previewHost.frame.width, 239)
        let pane = try XCTUnwrap(delegate.current?.editor)
        let glyph = ("0" as NSString).size(withAttributes: [.font: EditorTheme.font(size: 28)]).width
        XCTAssertGreaterThanOrEqual(pane.scrollView.contentSize.width - 34, 20 * glyph - 1)
        delegate.window.setContentSize(NSSize(width: 1600, height: 700))
        delegate.window.contentView?.layoutSubtreeIfNeeded()
        delegate.split.setPosition(900, ofDividerAt: 0)
        delegate.split.splitViewDidResizeSubviews(Notification(name: NSSplitView.didResizeSubviewsNotification))
        XCTAssertEqual(delegate.editorHost.frame.width, 900, accuracy: 2)
        delegate.togglePreview()
        XCTAssertEqual(delegate.editorHost.frame.width, delegate.split.bounds.width, accuracy: 1)
        delegate.togglePreview()
        XCTAssertEqual(delegate.editorHost.frame.width, 900, accuracy: 2)
        delegate.window.setContentSize(NSSize(width: 1120, height: 600))
        delegate.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(delegate.editorHost.frame.width / (delegate.split.bounds.width - delegate.split.dividerThickness), 900 / 1599, accuracy: 0.02)
    }
}
