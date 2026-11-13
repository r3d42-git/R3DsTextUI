import Foundation
import XCTest
@testable import TextUICore

final class SearchTests: XCTestCase {
    func testLiteralSearchEscapesMetacharactersAndUsesUTF16Ranges() throws {
        let text = "😀 A.b a.b axb"
        XCTAssertEqual(try SearchOptions().matches(in: text, query: "a.b"), [NSRange(location: 3, length: 3), NSRange(location: 7, length: 3)])
        XCTAssertEqual(try SearchOptions(caseSensitive: true).matches(in: text, query: "a.b"), [NSRange(location: 7, length: 3)])
        XCTAssertEqual(try SearchOptions().matches(in: text, query: ""), [])
    }

    func testRegexAndInvalidExpression() throws {
        XCTAssertEqual(try SearchOptions(regex: true).matches(in: "a12 b345", query: "\\d+"), [NSRange(location: 1, length: 2), NSRange(location: 5, length: 3)])
        XCTAssertThrowsError(try SearchOptions(regex: true).matches(in: "text", query: "["))
    }

    func testWholeWordRespectsUnicodeLettersNumbersAndUnderscores() throws {
        let text = "cat scatter cat2 _cat cat_ 猫cat caté (cat) CAT"
        let matches = try SearchOptions(wholeWord: true).matches(in: text, query: "cat")
        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(matches.map { (text as NSString).substring(with: $0) }, ["cat", "cat", "CAT"])
    }

    func testLineStartsHandleEmptyTextMixedNewlinesAndTrailingEmptyLine() {
        XCTAssertEqual(TextNavigation.lineStarts(""), [0])
        XCTAssertEqual(TextNavigation.lineStarts("a\r\nb\nc\rd"), [0, 3, 5, 7])
        XCTAssertEqual(TextNavigation.lineStarts("😀\r\nlast\n"), [0, 4, 9])
        XCTAssertEqual(TextNavigation.lineStarts("one line"), [0])
    }

    func testPositionCountsGraphemesAndClampsOutOfBounds() {
        let text = "😀e\u{301}\nnext"
        let firstLineEnd = TextNavigation.position(text, at: 4)
        XCTAssertEqual(firstLineEnd.line, 1)
        XCTAssertEqual(firstLineEnd.column, 3)
        let secondLine = TextNavigation.position(text, at: 5)
        XCTAssertEqual(secondLine.line, 2)
        XCTAssertEqual(secondLine.column, 1)
        XCTAssertEqual(TextNavigation.position(text, at: -1).column, 1)
        XCTAssertEqual(TextNavigation.position(text, at: 999).line, 2)
        XCTAssertEqual(TextNavigation.position(text, at: 999).column, 5)
    }

    func testUnicodeSeparatorsAtEOFCreateAnEmptyFinalLine() {
        for separator in ["\n", "\r", "\r\n", "\u{2028}", "\u{2029}"] {
            let text = "😀" + separator
            let end = text.utf16.count
            XCTAssertEqual(TextNavigation.lineStarts(text), [0, end], "Separator: \(separator.debugDescription)")
            let position = TextNavigation.position(text, at: end)
            XCTAssertEqual(position.line, 2)
            XCTAssertEqual(position.column, 1)
        }
        XCTAssertEqual(TextNavigation.lineStarts("a\u{2028}b\u{2029}"), [0, 2, 4])
    }

    func testIndexedPositionPreservesCRLFAndGraphemeColumns() {
        let text = "👩🏽‍💻e\u{301}\r\nnext\u{2028}\u{2029}"
        let starts = TextNavigation.lineStarts(text)
        for location in [-1] + Array(0...text.utf16.count) + [Int.max] {
            let indexed = TextNavigation.position(text, at: location, lineStarts: starts)
            let original = TextNavigation.position(text, at: location)
            XCTAssertEqual(indexed.line, original.line)
            XCTAssertEqual(indexed.column, original.column)
        }
        let firstLineEnd = "👩🏽‍💻e\u{301}".utf16.count
        let position = TextNavigation.position(text, at: firstLineEnd, lineStarts: starts)
        XCTAssertEqual(position.line, 1)
        XCTAssertEqual(position.column, 3)
        XCTAssertEqual(starts, [0, firstLineEnd + 2, firstLineEnd + 7, firstLineEnd + 8])
        XCTAssertEqual(TextNavigation.position(text, at: firstLineEnd + 1, lineStarts: starts).line, 1,
                       "The UTF-16 offset inside CRLF must stay on the preceding line")
    }

    func testMarkdownAndHTMLOutlineLocationsAreEditorOffsets() {
        let markdown = "😀 intro\n# First\ntext\n## Second"
        let headings = TextNavigation.outline(markdown, format: .markdown)
        XCTAssertEqual(headings.map(\.title), ["First", "Second"])
        XCTAssertEqual(headings.first?.location, (markdown as NSString).range(of: "# First").location)
        let html = "<p>😀</p><H2 class=\"title\">A <em>heading</em></H2>"
        let htmlHeadings = TextNavigation.outline(html, format: .html)
        XCTAssertEqual(htmlHeadings.map(\.title), ["A heading"])
        XCTAssertEqual(htmlHeadings.first?.location, (html as NSString).range(of: "<H2").location)
        XCTAssertTrue(TextNavigation.outline(markdown, format: .text).isEmpty)
    }
}
