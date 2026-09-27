import Foundation
import XCTest
@testable import TextUICore

final class DokuWikiSyntaxTests: XCTestCase {
    func testRecognitionRequiresIndependentWikiSignals() {
        XCTAssertTrue(DokuWikiSyntax.isLikelyDocument("==== Anleitung ====\n<code>print(1)</code>"))
        XCTAssertTrue(DokuWikiSyntax.isLikelyDocument("====== Titel ======\n==== Kapitel ===="))
        XCTAssertTrue(DokuWikiSyntax.isLikelyDocument(#"[[seite|Link]] und ein Umbruch \\ "#))
        for plain in ["Normaler Text", "====", "==== Decoration ====", "==== Wrong =====\n== Also wrong ===", #"C:\Users\name \\server\share"#, "<code>an HTML example</code>", "[[an example]]", "<code>==== Hidden ====\n[[hidden]]</code>"] {
            XCTAssertFalse(DokuWikiSyntax.isLikelyDocument(plain), plain)
        }
    }

    func testRecognitionIsBoundedAndUnicodeSafe() {
        let suffix = "\n==== Titel ====\n[[seite]]"
        XCTAssertFalse(DokuWikiSyntax.isLikelyDocument(String(repeating: "😀", count: 32_768) + suffix))
        XCTAssertTrue(DokuWikiSyntax.isLikelyDocument("😀\n" + suffix))
    }

    func testOutlineExcludesLiteralBlocksAndPreservesUTF16Offsets() {
        let text = "😀\r\n====== Übersicht ======\r\n<code swift>\r\n==== Code ====\r\n</code>\r\n<file>\n==== Datei ====\n</file>\n<nowiki>\n==== Literal ====\n</nowiki>\n%%\n==== Escape ====\n%%\n== Ende ==\n<code>\n==== Unfertig ===="
        let entries = TextNavigation.outline(text, format: .dokuwiki)
        XCTAssertEqual(entries.map(\.title), ["Übersicht", "Ende"])
        XCTAssertEqual(entries.map(\.location), [(text as NSString).range(of: "====== Übersicht").location, (text as NSString).range(of: "== Ende ==").location])
    }

    func testEditorPaletteAndLiteralPrecedence() {
        let text = "😀\n==== Überschrift ====\n**Wichtig** und ''mono'' [[seite|Link]]\n<code>**literal**\n==== kein Titel ====</code>"
        let spans = SyntaxHighlighting.spans(in: text, format: .dokuwiki)
        func color(_ needle: String) -> SyntaxKind? {
            let location = (text as NSString).range(of: needle).location
            return spans.last { NSLocationInRange(location, $0.range) }?.kind
        }
        XCTAssertEqual(color("Überschrift"), .heading)
        XCTAssertEqual(color("Wichtig"), .strong)
        XCTAssertEqual(color("mono"), .string)
        XCTAssertEqual(color("seite"), .selector)
        XCTAssertEqual(color("literal"), .comment)
        XCTAssertEqual(color("kein Titel"), .comment)
        XCTAssertNil(color("und"))
    }
}
