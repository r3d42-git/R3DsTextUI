import AppKit
import XCTest
import TextUICore
@testable import TextUI

final class LineIndexTests: XCTestCase {
    @MainActor
    func testGutterAndPositionShareUnicodeAndCRLFLineIndex() {
        _ = NSApplication.shared
        let firstLine = "👩🏽‍💻e\u{301}"
        let source = firstLine + "\r\nnext\u{2028}\u{2029}"
        let pane = EditorPane(text: source, format: .text, fontSize: 14)
        XCTAssertEqual(pane.lineStarts, TextNavigation.lineStarts(source))
        XCTAssertEqual(pane.lineStarts, pane.gutter.lineStarts)
        XCTAssertEqual(pane.position(at: firstLine.utf16.count).column, 3)
        XCTAssertEqual(pane.position(at: firstLine.utf16.count + 2).line, 2)
        XCTAssertEqual(pane.position(at: source.utf16.count).line, 4)
        XCTAssertEqual(pane.position(at: source.utf16.count).column, 1)
    }

    @MainActor
    func testEditsRefreshIndexBeforeChangeCallback() {
        _ = NSApplication.shared
        let pane = EditorPane(text: "😀\r\nend", format: .text, fontSize: 14)
        var snapshots: [[Int]] = []
        pane.onChange = { snapshots.append(pane.lineStarts) }
        pane.textView.insertText("\u{2028}", replacementRange: NSRange(location: 7, length: 0))
        XCTAssertEqual(pane.lineStarts, [0, 4, 8])
        XCTAssertEqual(snapshots.last, pane.lineStarts)
        XCTAssertEqual(pane.position(at: 8).line, 3)
        pane.textView.insertText("", replacementRange: NSRange(location: 0, length: 4))
        XCTAssertEqual(pane.lineStarts, [0, 4])
        XCTAssertEqual(pane.position(at: 4).line, 2)

        pane.textView.string = ""
        pane.textView.didChangeText()
        XCTAssertEqual(pane.lineStarts, [0])
        XCTAssertEqual(pane.position(at: Int.max).line, 1)
        XCTAssertEqual(pane.position(at: Int.max).column, 1)
        XCTAssertEqual(snapshots.last, [0])
    }

    @MainActor
    func testRepeatedSelectionsInLargeDocumentReuseIndexStorage() {
        _ = NSApplication.shared
        let line = "😀e\u{301}\r\n"
        let lineLength = line.utf16.count
        let lineCount = 20_000
        let pane = EditorPane(text: String(repeating: line, count: lineCount), format: .text, fontSize: 14)
        pane.setMinimapVisible(false)
        let initialIndex = pane.lineStarts
        XCTAssertEqual(initialIndex.count, lineCount + 1)
        var selectionCallbacks = 0
        pane.onSelection = {
            selectionCallbacks += 1
            let position = pane.position(at: pane.textView.selectedRange().location)
            XCTAssertEqual(position.column, 3)
        }
        initialIndex.withUnsafeBufferPointer { original in
            for step in 0..<128 {
                let lineNumber = (step * 157) % lineCount
                let offset = lineNumber * lineLength + 4
                pane.textView.setSelectedRange(NSRange(location: offset, length: 0))
                let position = pane.position(at: offset)
                XCTAssertEqual(position.line, lineNumber + 1)
                XCTAssertEqual(position.column, 3)
                pane.lineStarts.withUnsafeBufferPointer { current in
                    XCTAssertEqual(current.baseAddress, original.baseAddress,
                                   "Selection and status queries must retain the existing index buffer")
                }
            }
        }
        XCTAssertGreaterThan(selectionCallbacks, 0)
        XCTAssertEqual(pane.lineStarts, initialIndex)
    }

    @MainActor
    func testAdaptiveMinimapPreservesTextSpaceAndReturnsAfterWidening() {
        _ = NSApplication.shared
        let pane = EditorPane(text: "👩🏽‍💻\t" + String(repeating: "Lange deutsche Wörter ", count: 30), format: .text, fontSize: 28)
        func resize(_ width: CGFloat) {
            pane.view.setFrameSize(NSSize(width: width, height: 500))
            pane.view.layoutSubtreeIfNeeded()
            pane.finishLayout()
        }
        resize(900)
        XCTAssertFalse(pane.minimap.isHidden)
        XCTAssertEqual(pane.minimap.frame.width, 136, accuracy: 0.5)
        resize(540)
        XCTAssertFalse(pane.minimap.isHidden)
        XCTAssertLessThan(pane.minimap.frame.width, 136)
        XCTAssertGreaterThanOrEqual(pane.minimap.frame.width, 64)
        let font = EditorTheme.font(size: 28)
        let minimum = 20 * ("0" as NSString).size(withAttributes: [.font: font]).width
        let actual = pane.scrollView.contentSize.width - 2 * pane.textView.textContainerInset.width
            - 2 * (pane.textView.textContainer?.lineFragmentPadding ?? 0)
        XCTAssertGreaterThanOrEqual(actual, minimum - 1)
        resize(320)
        XCTAssertTrue(pane.minimap.isHidden)
        XCTAssertEqual(pane.minimap.frame.width, 0, accuracy: 0.5)
        resize(900)
        XCTAssertFalse(pane.minimap.isHidden)
        XCTAssertEqual(pane.minimap.frame.width, 136, accuracy: 0.5)
        resize(540)
        pane.updateAppearance(format: .text, fontSize: 14, wrap: true)
        pane.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(pane.minimap.frame.width, 136, accuracy: 0.5)
        pane.setMinimapVisible(false)
        resize(320)
        resize(900)
        XCTAssertTrue(pane.minimap.isHidden, "Automatic restoration must honor the user's off preference")
        XCTAssertEqual(pane.minimap.frame.width, 0, accuracy: 0.5)
    }
}
