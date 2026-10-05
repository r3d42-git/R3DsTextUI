import AppKit
import XCTest
import TextUICore
@testable import TextUI

final class EditorPaneTests: XCTestCase {
    @MainActor
    func testNativeDocumentFrameGrowsForScrollAndShrinksAfterDeletion() throws {
        _ = NSApplication.shared
        let source = String(repeating: String(repeating: "Wort ", count: 100) + "\n", count: 80)
        let pane = EditorPane(text: source, format: .text, fontSize: 14)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = pane.view
        defer { window.close() }
        let container = try XCTUnwrap(pane.textView.textContainer)
        let layout = try XCTUnwrap(pane.textView.layoutManager)
        for wrap in [true, false, true] {
            pane.updateAppearance(format: .text, fontSize: 14, wrap: wrap)
            pane.view.layoutSubtreeIfNeeded()
            pane.finishLayout()
            // This intentionally small document validates completed layout size.
            layout.ensureLayout(for: container)
            pane.finishLayout()
            XCTAssertGreaterThan(pane.textView.frame.height, pane.scrollView.contentSize.height)
            if wrap {
                XCTAssertEqual(pane.textView.frame.width, pane.scrollView.contentSize.width, accuracy: 1)
            } else {
                XCTAssertGreaterThan(pane.textView.frame.width, pane.scrollView.contentSize.width)
            }
            let clip = pane.scrollView.contentView
            clip.scroll(to: NSPoint(x: 0, y: 600))
            pane.scrollView.reflectScrolledClipView(clip)
            XCTAssertGreaterThan(clip.bounds.minY, 0)
        }
        pane.textView.string = "Kurzer Text."
        pane.textDidChange(Notification(name: NSText.didChangeNotification, object: pane.textView))
        layout.ensureLayout(for: container)
        pane.finishLayout()
        XCTAssertEqual(pane.textView.frame.height, pane.scrollView.contentSize.height, accuracy: 1)
        XCTAssertEqual(pane.scrollView.contentView.bounds.minY, 0, accuracy: 1)
        XCTAssertEqual(pane.textView.string, "Kurzer Text.")
    }

    @MainActor
    func testOpeningAndResizingDocumentAppliesWrapWithoutToggling() async throws {
        _ = NSApplication.shared
        let source = String(repeating: "Langer Absatz mit mehreren Worten. ", count: 80)
        let pane = EditorPane(text: source, format: .markdown, fontSize: 18)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        let window = NSWindow(contentRect: host.bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        host.addSubview(pane.view)
        pane.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pane.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            pane.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            pane.view.topAnchor.constraint(equalTo: host.topAnchor),
            pane.view.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        for width in [CGFloat(900), 420, 1100] {
            host.setFrameSize(NSSize(width: width, height: 500))
            host.layoutSubtreeIfNeeded()
            // Reproduce a provisional oversized document frame left by initial
            // attachment. The requested wrap state itself has not changed.
            pane.textView.setFrameSize(NSSize(width: 2400, height: 500))
            pane.updateAppearance(format: .markdown, fontSize: 18, wrap: true)
            pane.finishLayout()
            window.displayIfNeeded()
            try await Task.sleep(nanoseconds: 50_000_000)
            let container = try XCTUnwrap(pane.textView.textContainer)
            let layout = try XCTUnwrap(pane.textView.layoutManager)
            XCTAssertEqual(pane.textView.frame.width, pane.scrollView.contentSize.width, accuracy: 1)
            XCTAssertEqual(container.containerSize.width, pane.scrollView.contentSize.width - 24, accuracy: 1)
            layout.ensureLayout(for: container)
            var lineCount = 0
            layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { rect, _, _, _, _ in
                XCTAssertLessThanOrEqual(rect.maxX, container.containerSize.width + 1)
                lineCount += 1
            }
            XCTAssertGreaterThan(lineCount, 5, "Opening must actually produce wrapped line fragments")
        }
        XCTAssertEqual(pane.textView.string, source)
        withExtendedLifetime(host) {}
    }

    @MainActor
    func testLargeEmbeddedDataKeepsWrappingColorsAndTextDuringZoom() async throws {
        _ = NSApplication.shared
        // A long physical line is materially different from many short lines:
        // wrapping it forces the native layout engine to process the whole line.
        let source = "<script>const embedded = \"data:image/png;base64," + String(repeating: "A", count: 5 * 1024 * 1024) + "\";</script>\r\n<p>Ende 🦊</p>\r\n"
        let pane = EditorPane(text: source, format: .html, fontSize: 14)
        XCTAssertEqual(pane.textView.textContainer?.widthTracksTextView, true)
        XCTAssertFalse(pane.textView.isHorizontallyResizable)
        XCTAssertFalse(pane.scrollView.hasHorizontalScroller)

        let selection = NSRange(location: (source as NSString).length - 4, length: 0)
        pane.textView.setSelectedRange(selection)
        var changes = 0
        pane.onChange = { changes += 1 }
        for size in [CGFloat(18), 12, 20, 14] {
            pane.updateAppearance(format: .html, fontSize: size, wrap: true)
            XCTAssertEqual(pane.textView.textContainer?.widthTracksTextView, true)
            XCTAssertEqual(pane.textView.selectedRange(), selection)
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(pane.textView.string, source)
        XCTAssertEqual(changes, 0, "Display changes must not mark a document edited")
        XCTAssertNotNil(pane.textView.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil), "Visible HTML must retain syntax colors in large files")
    }

    @MainActor
    func testOrdinaryDocumentWrapCanBeToggledWithoutChangingContent() async {
        _ = NSApplication.shared
        let source = "# Überschrift\r\n" + String(repeating: "Eine normale Zeile.\r\n", count: 2500)
        let pane = EditorPane(text: source, format: .markdown, fontSize: 14)
        XCTAssertEqual(pane.textView.textContainer?.widthTracksTextView, true)
        pane.updateAppearance(format: .markdown, fontSize: 14, wrap: false)
        XCTAssertEqual(pane.textView.textContainer?.widthTracksTextView, false)
        XCTAssertTrue(pane.scrollView.hasHorizontalScroller)
        pane.updateAppearance(format: .markdown, fontSize: 18, wrap: true)
        XCTAssertEqual(pane.textView.textContainer?.widthTracksTextView, true)
        XCTAssertFalse(pane.textView.isHorizontallyResizable)
        XCTAssertFalse(pane.scrollView.hasHorizontalScroller)
        XCTAssertEqual(pane.textView.string, source)
    }

    @MainActor
    func testTextViewportStaysOutsideGutterAfterZoomAndHorizontalScroll() async throws {
        _ = NSApplication.shared
        let source = String(repeating: "A long line with content. ", count: 100) + "\nEnde\n"
        let pane = EditorPane(text: source, format: .text, fontSize: 14)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        pane.view.frame = host.bounds
        host.addSubview(pane.view)

        for size in [CGFloat(14), 22, 12, 18] {
            pane.updateAppearance(format: .text, fontSize: size, wrap: false)
            host.layoutSubtreeIfNeeded()
            pane.finishLayout()
            let gutter = try XCTUnwrap(pane.view.subviews.first(where: { $0 !== pane.scrollView }))
            let gutterRect = pane.view.convert(gutter.bounds, from: gutter)
            let clip = pane.scrollView.contentView
            let viewport = pane.view.convert(clip.bounds, from: clip)
            XCTAssertGreaterThanOrEqual(viewport.minX, gutterRect.maxX - 0.5, "The text viewport must start after the line-number gutter")

            clip.scroll(to: .zero)
            pane.scrollView.reflectScrolledClipView(clip)
            let textStart = pane.view.convert(pane.textView.textContainerOrigin, from: pane.textView)
            XCTAssertGreaterThanOrEqual(textStart.x, gutterRect.maxX, "The first character must remain to the right of the gutter after zoom")

            clip.scroll(to: NSPoint(x: 120, y: 0))
            pane.scrollView.reflectScrolledClipView(clip)
            XCTAssertTrue(clip.clipsToBounds, "Horizontally scrolled text must be clipped before it reaches the gutter")
        }
        XCTAssertEqual(pane.textView.string, source)
        // Keep the detached host alive until all native geometry checks finish.
        withExtendedLifetime(host) {}
    }

    @MainActor
    func testFontOnlyChangeDoesNotRecomputeSyntaxColors() async throws {
        _ = NSApplication.shared
        let pane = EditorPane(text: "<p>Hallo</p>\n", format: .html, fontSize: 14)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let layout = try XCTUnwrap(pane.textView.layoutManager)
        XCTAssertNotNil(layout.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil), "The initial syntax pass must have run")

        // A temporary marker makes an unwanted second syntax pass observable:
        // the highlighter clears foreground attributes before recoloring tags.
        let marker = NSColor.magenta
        layout.addTemporaryAttribute(.foregroundColor, value: marker, forCharacterRange: NSRange(location: 1, length: 1))
        pane.updateAppearance(format: .html, fontSize: 20, wrap: true)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(layout.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil) as? NSColor, marker)
        XCTAssertEqual(pane.textView.string, "<p>Hallo</p>\n")
    }
}
