import AppKit
import XCTest
import TextUICore
@testable import TextUI

final class MinimapTests: XCTestCase {
    func testUnicodeCRLFTrailingLineAndNavigation() {
        let document = MinimapDocument(text: "🦊abc\r\n\r\n12345678\n", spans: [])
        XCTAssertEqual(document.lines.map(\.start), [0, 7, 9, 18])
        XCTAssertEqual(document.row(at: 13), 2)
        XCTAssertEqual(document.location(atRow: -1), 0)
        XCTAssertEqual(document.location(atRow: 999), 18)
        XCTAssertEqual(MinimapDocument(text: "", spans: []).lines.count, 1)
    }

    func testBoundedElevenMegabyteLongLineAndSyntaxPrecedence() {
        let text = "<p>" + String(repeating: "A", count: 11 * 1024 * 1024) + "</p>\n"
        let length = (text as NSString).length
        let document = MinimapDocument(text: text, spans: [
            SyntaxSpan(range: NSRange(location: 0, length: length), kind: .string),
            SyntaxSpan(range: NSRange(location: 0, length: 3), kind: .tag)
        ])
        let snapshot = MinimapSnapshot(document: document, firstRow: 0, rows: 1000)
        XCTAssertEqual(document.lines.count, 2)
        XCTAssertEqual(snapshot.height, 2)
        XCTAssertEqual(snapshot.pixels[0], MinimapSnapshot.code(.tag))
        XCTAssertEqual(snapshot.pixels[4], MinimapSnapshot.code(.string))
        XCTAssertEqual(document.location(atRow: 1), length)
        let manyLines = MinimapDocument(text: String(repeating: "  content\n", count: 100_000), spans: [])
        let tile = MinimapSnapshot(document: manyLines, firstRow: 70_000, rows: 10_000)
        XCTAssertEqual(tile.height, MinimapSnapshot.maximumHeight)
        XCTAssertEqual(tile.pixels.count, MinimapSnapshot.width * MinimapSnapshot.maximumHeight)
        XCTAssertEqual(tile.firstRow, 70_000)
    }

    func testTileKeepsBlankRowsIndentationAndTabs() {
        let document = MinimapDocument(text: "ignored\n\tA\n\n    B\n", spans: [])
        let tile = MinimapSnapshot(document: document, firstRow: 1, rows: 3)
        XCTAssertEqual(tile.pixels[0], 0)
        XCTAssertEqual(tile.pixels[4], 1)
        XCTAssertEqual(Array(tile.pixels[96..<192]), [UInt8](repeating: 0, count: 96))
        XCTAssertEqual(tile.pixels[192 + 4], 1)
    }

    @MainActor
    func testMinimapGeometryAndTogglePreserveDocumentAndSelection() {
        _ = NSApplication.shared
        let text = String(repeating: "<p>Test</p>\n", count: 300)
        let pane = EditorPane(text: text, format: .html, fontSize: 14)
        pane.view.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        pane.view.layoutSubtreeIfNeeded()
        let selection = NSRange(location: 20, length: 5)
        pane.textView.setSelectedRange(selection)
        XCTAssertEqual(pane.minimap.frame.width, 136, accuracy: 0.5)
        XCTAssertEqual(pane.scrollView.frame.maxX, pane.minimap.frame.minX, accuracy: 0.5)
        XCTAssertEqual(pane.minimap.frame.maxX, pane.view.bounds.maxX, accuracy: 0.5)
        let visibleWidth = pane.scrollView.frame.width
        pane.setMinimapVisible(false)
        XCTAssertTrue(pane.minimap.isHidden)
        XCTAssertEqual(pane.scrollView.frame.width, visibleWidth + 136, accuracy: 0.5)
        pane.setMinimapVisible(true)
        XCTAssertFalse(pane.minimap.isHidden)
        XCTAssertEqual(pane.textView.string, text)
        XCTAssertEqual(pane.textView.selectedRange(), selection)
        XCTAssertTrue(pane.textView.layoutManager?.allowsNonContiguousLayout == true)
        XCTAssertTrue(pane.textView.layoutManager?.backgroundLayoutEnabled == false)
    }
    @MainActor
    func testNativeNavigationPreservesSelectionTextAndHorizontalScroll() async throws {
        _ = NSApplication.shared
        let line = String(repeating: "abcdefghij ", count: 100) + "\n"
        let text = String(repeating: line, count: 500)
        let pane = EditorPane(text: text, format: .text, fontSize: 14)
        pane.view.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        pane.updateAppearance(format: .text, fontSize: 14, wrap: false)
        pane.view.layoutSubtreeIfNeeded()
        pane.finishLayout()
        pane.textView.setSelectedRange(NSRange(location: 20, length: 8))
        let clip = pane.scrollView.contentView
        clip.scroll(to: NSPoint(x: 120, y: 0))
        let horizontal = clip.bounds.minX
        try await Task.sleep(nanoseconds: 400_000_000)
        let initialViewport = pane.minimap.viewportRect
        pane.minimap.onNavigate?((line as NSString).length * 300)
        XCTAssertGreaterThan(clip.bounds.minY, 500)
        let layout = try XCTUnwrap(pane.textView.layoutManager)
        let glyph = layout.glyphIndexForCharacter(at: (line as NSString).length * 300)
        let targetRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
        XCTAssertEqual(clip.bounds.minY, targetRect.minY + pane.textView.textContainerOrigin.y, accuracy: 0.5)
        XCTAssertGreaterThan(pane.minimap.viewportRect.minY, initialViewport.minY + 100)
        XCTAssertEqual(pane.minimap.viewportRect.minY, pane.minimap.bounds.height * 0.6, accuracy: 3,
                       "At source line 300 of 500 the viewport follows the available overview height, including the space used by the column ruler")
        XCTAssertEqual(clip.bounds.minX, horizontal, accuracy: 0.5)
        XCTAssertEqual(pane.textView.selectedRange(), NSRange(location: 20, length: 8))
        XCTAssertEqual(pane.textView.string, text)
        pane.minimap.onNavigate?(0)
        XCTAssertEqual(clip.bounds.minY, 0, accuracy: 0.5)
        XCTAssertEqual(pane.minimap.viewportRect.minY, initialViewport.minY, accuracy: 1)
    }

    @MainActor
    func testShortOverviewUsesCompactHeightAndMatchingViewport() async throws {
        let map = EditorMinimap(frame: NSRect(x: 0, y: 0, width: 136, height: 500))
        map.update(text: "one\ntwo\nthree", spans: [])
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(map.contentRect.height, 9)
        map.updateViewport(NSRange(location: 4, length: 3))
        XCTAssertLessThanOrEqual(map.viewportRect.maxY, map.contentRect.maxY)
    }

}
