import XCTest
@testable import TextUICore

final class DokuWikiPreviewTests: XCTestCase {
    private func body(_ source: String) -> String {
        let html = DokuWikiPreview.html(from: source)
        return String(html.components(separatedBy: "<main>").last!.components(separatedBy: "</main>").first!)
    }

    func testHeadingsAndInlineFormatting() {
        XCTAssertEqual(body("====== Titel ======\n==== Abschnitt ====\n**fett** //kursiv// __unterstrichen__ ''mono''"),
                       "<h1>Titel</h1><h3>Abschnitt</h3><p><strong>fett</strong> <em>kursiv</em> <u>unterstrichen</u> <code>mono</code></p>")
        XCTAssertEqual(body("==== kein Titel ==="), "<p>==== kein Titel ===</p>")
        XCTAssertEqual(body("<sub>2</sub><sup>3</sup><del>alt</del>"), "<p><sub>2</sub><sup>3</sup><del>alt</del></p>")
    }

    func testLiteralRegionsNeverInterpretFormattingOrHTML() {
        let source = "vor <code bash>echo **test** & <script>alert(1)</script></code> nach\n\n<file txt>==== Title ====\n\\\\</file>\n\n<nowiki>**literal** <b>x</b></nowiki> %%//literal//%%"
        let rendered = body(source)
        XCTAssertTrue(rendered.contains("<code>echo **test** &amp; &lt;script&gt;alert(1)&lt;/script&gt;</code>"))
        XCTAssertTrue(rendered.contains("<pre><code>==== Title ====\n\\\\</code></pre>"))
        XCTAssertTrue(rendered.contains("<p>**literal** &lt;b&gt;x&lt;/b&gt; //literal//</p>"))
        XCTAssertFalse(rendered.contains("<script>"))
        XCTAssertFalse(rendered.contains("<strong>"))
        XCTAssertFalse(rendered.contains("WIKILITERAL"))
        XCTAssertEqual(body("<code>\n😀 <x>\r\n</code>"), "<pre><code>😀 &lt;x&gt;\n</code></pre>")
    }

    func testBreaksLinksAndURLSchemes() {
        XCTAssertEqual(body(#"eins\\ zwei\\drei\\"#), "<p>eins<br> zwei\\\\drei<br></p>")
        let rendered = body("https://example.org/path https://other.org\n[[https://example.org/?a=1&b=2|**Link**]] [[wiki:intern|Intern]] [[javascript:alert(1)|unsicher]]")
        XCTAssertFalse(rendered.contains("<em>"))
        XCTAssertTrue(rendered.contains("<a href=\"https://example.org/?a=1&amp;b=2\"><strong>Link</strong></a>"))
        XCTAssertTrue(rendered.contains("<span>Intern</span>"))
        XCTAssertFalse(rendered.contains("href=\"javascript:"))
        XCTAssertEqual(body("<img src=x onerror=alert(1)>"), "<p>&lt;img src=x onerror=alert(1)&gt;</p>")
    }

    func testNestedListsAndTableLinkSeparators() {
        XCTAssertEqual(body("  * Erst\n    - Unterpunkt\n    - Zweiter\n  * Ende\n  - Nummer"),
                       "<ul><li>Erst<ol><li>Unterpunkt</li><li>Zweiter</li></ol></li><li>Ende</li></ul><ol><li>Nummer</li></ol>")
        XCTAssertEqual(body("^ Name ^ Wert ^\n| [[https://example.org|Link]] | **Wert** |"),
                       "<div class=\"table-scroll\"><table><tr><th>Name</th><th>Wert</th></tr><tr><td><a href=\"https://example.org\">Link</a></td><td><strong>Wert</strong></td></tr></table></div>")
        XCTAssertTrue(body("|  mittig  |  rechts |" ).contains("<td align=\"center\">mittig</td><td align=\"right\">rechts</td>"))
    }

    func testQuoteParagraphsAndMalformedSyntaxRemainReadable() {
        XCTAssertEqual(body("> Erst\n>> Tiefer\n\nDanach\nweiter\n\n----"),
                       "<blockquote><p>Erst</p><blockquote><p>Tiefer</p></blockquote></blockquote><p>Danach\nweiter</p><hr>")
        XCTAssertEqual(body("**offen [[offen <code>offen"), "<p>**offen [[offen <code>offen</code></p>")
        XCTAssertEqual(body("<code>\n==== Beispiel ====\n**literal**"), "<pre><code>==== Beispiel ====\n**literal**</code></pre>")
        XCTAssertEqual(body("<nowiki>**literal**"), "<p>**literal**</p>")
        XCTAssertEqual(body("%%**literal**"), "<p>**literal**</p>")
        XCTAssertEqual(body("[[]]"), "<p><span></span></p>")
        XCTAssertEqual(body("  - Befehl <code>echo test</code>\n  - Weiter <code>ls</code>"), "<ol><li>Befehl <code>echo test</code></li><li>Weiter <code>ls</code></li></ol>")
    }
}
