import AppKit
import XCTest
import TextUICore
@testable import TextUI

final class RulerTests: XCTestCase {
    @MainActor
    private func attachToWindow(_ pane: EditorPane, width: CGFloat = 900) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = pane.view
        pane.view.layoutSubtreeIfNeeded()
        pane.finishLayout()
        window.makeFirstResponder(pane.textView)
        return window
    }

    @MainActor
    func testCaretMarkerUsesNativeTabUnicodeWrapAndZoomPositions() throws {
        let source = "A\t👩🏽‍💻e\u{301}Z " + String(repeating: "abcdef ", count: 30)
        let pane = EditorPane(text: source, format: .text, fontSize: 14)
        let window = attachToWindow(pane, width: 450)
        defer { window.close() }
        let layout = try XCTUnwrap(pane.textView.layoutManager)
        let container = try XCTUnwrap(pane.textView.textContainer)
        let text = source as NSString
        let positions = [0, 1, 2, text.range(of: "e\u{301}").location, text.range(of: "Z").location, text.length - 3]
        for size in [CGFloat(14), 24] {
            pane.updateAppearance(format: .text, fontSize: size, wrap: true)
            pane.view.layoutSubtreeIfNeeded()
            pane.finishLayout()
            layout.ensureLayout(for: container)
            for position in positions {
                pane.textView.setSelectedRange(NSRange(location: position, length: 0))
                pane.textView.scrollRangeToVisible(pane.textView.selectedRange())
                let glyph = layout.glyphIndexForCharacter(at: position)
                let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let glyphPoint = layout.location(forGlyphAt: glyph)
                let textPoint = NSPoint(x: fragment.minX + glyphPoint.x + pane.textView.textContainerOrigin.x, y: 0)
                let expected = pane.columnRuler.convert(textPoint, from: pane.textView).x
                XCTAssertEqual(try XCTUnwrap(pane.columnRuler.caretPosition), expected, accuracy: 0.5)
            }
        }
        // The final insertion position belongs to a wrapped visual fragment.
        let finalGlyph = layout.glyphIndexForCharacter(at: positions.last!)
        XCTAssertGreaterThan(layout.lineFragmentRect(forGlyphAt: finalGlyph, effectiveRange: nil).minY, 0)
        XCTAssertEqual(pane.textView.string, source)
    }

    @MainActor
    func testCaretMarkerAtEmptyDocumentLineEndAndTrailingNewline() throws {
        for source in ["", "abc", "abc\n"] {
            let pane = EditorPane(text: source, format: .text, fontSize: 18)
            let window = attachToWindow(pane)
            pane.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
            pane.textView.scrollRangeToVisible(pane.textView.selectedRange())
            let expected = pane.columnRuler.position(ofColumn: source == "abc" ? 4 : 1)
            XCTAssertEqual(try XCTUnwrap(pane.columnRuler.caretPosition), expected, accuracy: 0.5)
            window.close()
        }
    }

    @MainActor
    func testCaretMarkerHidesForSelectionsAndOffscreenCursorAndTracksHorizontalScroll() throws {
        let source = String(repeating: "0123456789", count: 200) + "\n" + String(repeating: "line\n", count: 500)
        let pane = EditorPane(text: source, format: .text, fontSize: 14)
        let window = attachToWindow(pane)
        defer { window.close() }
        pane.updateAppearance(format: .text, fontSize: 14, wrap: false)
        pane.finishLayout()
        pane.textView.layoutManager?.ensureLayout(for: try XCTUnwrap(pane.textView.textContainer))
        pane.textView.setSelectedRange(NSRange(location: 40, length: 0))
        let start = try XCTUnwrap(pane.columnRuler.caretPosition)
        let clip = pane.scrollView.contentView
        clip.scroll(to: NSPoint(x: 120, y: 0))
        pane.scrollView.reflectScrolledClipView(clip)
        XCTAssertEqual(try XCTUnwrap(pane.columnRuler.caretPosition), start - clip.bounds.minX, accuracy: 0.5)
        pane.textView.setSelectedRange(NSRange(location: 40, length: 2))
        XCTAssertNil(pane.columnRuler.caretPosition)
        pane.textView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertNil(pane.columnRuler.caretPosition, "Horizontally clipped caret must not appear above the gutter")
        clip.scroll(to: NSPoint(x: 0, y: 800))
        pane.scrollView.reflectScrolledClipView(clip)
        XCTAssertNil(pane.columnRuler.caretPosition, "Minimap-like scrolling may leave the insertion point on an earlier line")
        clip.scroll(to: .zero)
        pane.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        XCTAssertNil(pane.columnRuler.caretPosition, "A distant cursor must not request insertion geometry for the offscreen paragraph")
        XCTAssertEqual(pane.textView.string, source)
    }

    @MainActor
    func testColumnGridMatchesNativeGlyphPositionsDuringScrollResizeAndZoom() throws {
        _ = NSApplication.shared
        let source = String(repeating: "0123456789", count: 100) + "\n\tTabbed\n"
        let pane = EditorPane(text: source, format: .text, fontSize: 14)
        pane.view.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        // Different insets and padding catch assumptions about the default 12+5.
        pane.textView.textContainerInset = NSSize(width: 19, height: 12)
        let container = try XCTUnwrap(pane.textView.textContainer)
        container.lineFragmentPadding = 7
        let layout = try XCTUnwrap(pane.textView.layoutManager)
        for size in [CGFloat(14), 28, 10] {
            pane.updateAppearance(format: .text, fontSize: size, wrap: false)
            for width in [CGFloat(900), 600] {
                pane.view.setFrameSize(NSSize(width: width, height: 500))
                pane.view.layoutSubtreeIfNeeded()
                pane.finishLayout()
                layout.ensureLayout(for: container)
                for offset in [CGFloat(0), 125, 487] {
                    let clip = pane.scrollView.contentView
                    clip.scroll(to: NSPoint(x: offset, y: 0))
                    pane.scrollView.reflectScrolledClipView(clip)
                    for column in [1, 10, 30, 100] {
                        let glyph = layout.glyphIndexForCharacter(at: column - 1)
                        let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                        let location = layout.location(forGlyphAt: glyph)
                        let nativePoint = NSPoint(x: fragment.minX + location.x + pane.textView.textContainerOrigin.x, y: 0)
                        let renderedX = pane.columnRuler.convert(nativePoint, from: pane.textView).x
                        XCTAssertEqual(pane.columnRuler.position(ofColumn: column), renderedX, accuracy: 0.1)
                    }
                    let viewport = pane.columnRuler.textViewport
                    let clipRect = pane.columnRuler.convert(clip.bounds, from: clip)
                    XCTAssertEqual(viewport.minX, clipRect.minX, accuracy: 0.1, "The corner above the line numbers must remain outside the scale")
                    XCTAssertEqual(viewport.maxX, clipRect.maxX, accuracy: 0.1, "The scale must stop before the minimap")
                }
            }
        }
        XCTAssertEqual(pane.textView.string, source)
    }

    @MainActor
    func testIndependentVisibilityReclaimsSpacePreservesSelectionAndUpdatesWrap() throws {
        _ = NSApplication.shared
        let source = String(repeating: "Normaler Absatz mit Worten und Tab\t. ", count: 100)
        let pane = EditorPane(text: source, format: .text, fontSize: 14)
        pane.view.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        pane.view.layoutSubtreeIfNeeded()
        pane.finishLayout()
        let original = pane.scrollView.frame.size
        let gutterWidth = pane.gutter.frame.width
        let rulerHeight = pane.columnRuler.frame.height
        let selection = NSRange(location: 27, length: 18)
        pane.textView.setSelectedRange(selection)
        var changes = 0
        pane.onChange = { changes += 1 }
        for columns in [false, true] {
            for lines in [false, true] {
                pane.setColumnRulerVisible(columns)
                pane.setLineNumbersVisible(lines)
                pane.finishLayout()
                XCTAssertEqual(pane.scrollView.frame.width, original.width + (lines ? 0 : gutterWidth), accuracy: 0.1)
                XCTAssertEqual(pane.scrollView.frame.height, original.height + (columns ? 0 : rulerHeight), accuracy: 0.1)
                XCTAssertEqual(pane.gutter.frame.width, lines ? gutterWidth : 0, accuracy: 0.1)
                XCTAssertEqual(pane.columnRuler.frame.height, columns ? rulerHeight : 0, accuracy: 0.1)
                XCTAssertEqual(pane.minimap.frame.height, pane.scrollView.frame.height, accuracy: 0.1)
                XCTAssertEqual(pane.textView.frame.width, pane.scrollView.contentSize.width, accuracy: 0.1)
                XCTAssertEqual(pane.textView.textContainer?.containerSize.width ?? 0, pane.scrollView.contentSize.width - 24, accuracy: 0.1)
                XCTAssertEqual(pane.textView.selectedRange(), selection)
                XCTAssertEqual(pane.textView.string, source)
                XCTAssertEqual(changes, 0)
            }
        }
    }

    @MainActor
    func testHiddenLineNumbersStayZeroWidthWhenLineCountAndFontChange() {
        _ = NSApplication.shared
        let pane = EditorPane(text: "short\n", format: .text, fontSize: 14)
        pane.view.frame = NSRect(x: 0, y: 0, width: 900, height: 500)
        pane.view.layoutSubtreeIfNeeded()
        let oldGutterWidth = pane.gutter.frame.width
        pane.setLineNumbersVisible(false)
        let expandedWidth = pane.scrollView.frame.width
        pane.textView.string = String(repeating: "line\n", count: 10_000)
        pane.textDidChange(Notification(name: NSText.didChangeNotification, object: pane.textView))
        pane.updateAppearance(format: .text, fontSize: 28, wrap: true)
        pane.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(pane.gutter.isHidden)
        XCTAssertEqual(pane.gutter.frame.width, 0, accuracy: 0.1)
        XCTAssertEqual(pane.scrollView.frame.width, expandedWidth, accuracy: 0.1)
        pane.setLineNumbersVisible(true)
        XCTAssertGreaterThan(pane.gutter.frame.width, oldGutterWidth)
        XCTAssertEqual(pane.scrollView.frame.width + pane.gutter.frame.width, expandedWidth, accuracy: 0.1)
    }
}
