import Foundation
import XCTest
@testable import TextUICore

final class SyntaxHighlightingTests: XCTestCase {
    func testLargeBundledDocumentsKeepHTMLAndCSSColorsWhileSkippingScriptBodies() {
        // Generated payload, never copied from a user's document. HTML-looking
        // strings and entities inside scripts must not allocate individual tokens.
        let payload = String(repeating: "<i class='x'>&amp;</i>", count: 550_000)
        let html = "<style>.a { color: red; }</style><script>" + payload + "</script><p class='after'>Done &amp;</p>"
        XCTAssertGreaterThan(html.utf8.count, 10 * 1024 * 1024)
        let start = Date()
        let spans = SyntaxHighlighting.spans(in: html, format: .html)
        let elapsed = Date().timeIntervalSince(start)
        print("Large generated HTML syntax: \(elapsed) seconds, \(spans.count) spans")
        XCTAssertLessThan(spans.count, 40)
        let property = (html as NSString).range(of: "color")
        XCTAssertTrue(spans.contains { $0.range == property && $0.kind == .tag })
        let trailingValue = (html as NSString).range(of: "'after'")
        XCTAssertTrue(spans.contains { $0.range == trailingValue && $0.kind == .string })
        let trailingEntity = (html as NSString).range(of: "&amp;", options: .backwards)
        XCTAssertTrue(spans.contains { $0.range == trailingEntity && $0.kind == .keyword })
    }

    func testLargeUnicodeDocumentsRetainTagHighlighting() {
        let text = "<p>" + String(repeating: "😀", count: 530_000) + "</p><b title='end'>"
        XCTAssertGreaterThan(text.utf8.count, 2 * 1024 * 1024)
        let spans = SyntaxHighlighting.spans(in: text, format: .html)
        let trailingValue = (text as NSString).range(of: "'end'")
        XCTAssertTrue(spans.contains { $0.range == trailingValue && $0.kind == .string })
    }

    private func color(_ needle: String, in text: String, format: DocumentFormat = .html) -> SyntaxKind? {
        let range = (text as NSString).range(of: needle)
        XCTAssertNotEqual(range.location, NSNotFound)
        return SyntaxHighlighting.spans(in: text, format: format).last {
            NSLocationInRange(range.location, $0.range)
        }?.kind
    }

    func testHTMLSeparatesTagsAttributesValuesAndPlainText() {
        let text = #"<div class="card" title="1 > 0" hidden>plain "quoted" 42px</div>"#
        XCTAssertEqual(color("div", in: text), .tag)
        XCTAssertEqual(color("class", in: text), .attribute)
        XCTAssertEqual(color("hidden", in: text), .attribute)
        XCTAssertEqual(color("card", in: text), .string)
        XCTAssertEqual(color("1 > 0", in: text), .string)
        XCTAssertEqual(color("<", in: text), .punctuation)
        XCTAssertNil(color("quoted", in: text))
        XCTAssertNil(color("42px", in: text))
    }

    func testEmbeddedCSSIsScopedAndPropertiesDoNotOverrideSelectors() {
        let text = "<style>.card:hover, #main { color: #ff8800; padding: 1.5rem; width: calc(100% - 2px); }</style><p>margin: 25px;</p>"
        XCTAssertEqual(color(".card", in: text), .selector)
        XCTAssertEqual(color("card", in: text), .selector)
        XCTAssertEqual(color("#main", in: text), .selector)
        XCTAssertEqual(color("color", in: text), .tag)
        XCTAssertEqual(color("padding", in: text), .tag)
        XCTAssertEqual(color("#ff8800", in: text), .keyword)
        XCTAssertEqual(color("1.5rem", in: text), .number)
        XCTAssertEqual(color("100%", in: text), .number)
        XCTAssertEqual(color("calc", in: text), .keyword)
        XCTAssertNil(color("25px", in: text))
        XCTAssertNil(color("margin", in: text))
    }

    func testCSSStringsAndCommentsOverrideTheirContentsWithoutCrossContamination() {
        let text = #"<style>.a { content: "/* fake */ 99px"; /* content: "x" 20px; */ color: red; }</style>"#
        XCTAssertEqual(color("fake", in: text), .string)
        XCTAssertEqual(color("99px", in: text), .string)
        XCTAssertEqual(color("20px", in: text), .comment)
        XCTAssertEqual(color("\"x\"", in: text), .comment)
        XCTAssertEqual(color("color", in: text), .tag)
    }

    func testHTMLCommentsOverrideFakeMarkupAndStyles() {
        let text = #"<!-- <style>.fake { color: 42px; }</style><div class="x"> --> <p title="real">OK</p>"#
        XCTAssertEqual(color("style", in: text), .comment)
        XCTAssertEqual(color("42px", in: text), .comment)
        XCTAssertEqual(color("class", in: text), .comment)
        XCTAssertEqual(color("real", in: text), .string)
    }

    func testUnfinishedStyleStillHighlightsAndUsesUTF16Offsets() {
        let text = "😀 Grüße <STYLE>.a { margin: 12px; content: \"日本語\";"
        let spans = SyntaxHighlighting.spans(in: text, format: .html)
        let number = (text as NSString).range(of: "12px")
        XCTAssertTrue(spans.contains { $0.range == number && $0.kind == .number })
        XCTAssertEqual(color("日本語", in: text), .string)
        XCTAssertEqual(color("margin", in: text), .tag)
        for span in spans {
            XCTAssertGreaterThan(span.range.length, 0)
            XCTAssertLessThanOrEqual(NSMaxRange(span.range), (text as NSString).length)
        }
    }

    func testScriptsDoNotReceiveHTMLAttributeOrCSSHighlighting() {
        let text = #"<script>const html = '<div class="fake">'; const css = 'margin: 20px';</script><p class="real">text</p>"#
        XCTAssertNil(color("fake", in: text))
        XCTAssertNil(color("20px", in: text))
        XCTAssertEqual(color("real", in: text), .string)
    }

    func testMarkdownAndPlainText() {
        let text = "# Heading\n**bold** and `code`\n```\n# sample\n```"
        XCTAssertEqual(color("Heading", in: text, format: .markdown), .heading)
        XCTAssertEqual(color("bold", in: text, format: .markdown), .strong)
        XCTAssertEqual(color("code", in: text, format: .markdown), .string)
        XCTAssertEqual(color("sample", in: text, format: .markdown), .comment)
        XCTAssertTrue(SyntaxHighlighting.spans(in: text, format: .text).isEmpty)
    }

    func testMarkdownReferencePaletteWithEmbeddedHTMLAndUnicode() {
        let text = "😀 Übersicht\r\n### Übergabe sichern\r\n| Funktion | Inhalt |\r\n| **Exportieren** | Arbeitsstand |\r\n1. Passwort vergeben\r\n<div class=\"warning\"><strong>Nicht verwechseln</strong></div>"
        XCTAssertEqual(color("Übergabe", in: text, format: .markdown), .heading)
        XCTAssertEqual(color("Exportieren", in: text, format: .markdown), .strong)
        XCTAssertEqual(color("div", in: text, format: .markdown), .tag)
        XCTAssertEqual(color("class", in: text, format: .markdown), .attribute)
        XCTAssertEqual(color("warning", in: text, format: .markdown), .string)
        for plain in ["Funktion", "Arbeitsstand", "Passwort", "Nicht verwechseln"] {
            XCTAssertNil(color(plain, in: text, format: .markdown))
        }
    }

    func testMarkdownCodeOverridesHTMLAndEmphasis() {
        let text = "`<span title='inline'>**literal**</span>`\n```html\n<div class='fenced'>**example**</div>\n```"
        for inline in ["span", "inline", "literal"] {
            XCTAssertEqual(color(inline, in: text, format: .markdown), .string)
        }
        for fenced in ["div", "fenced", "example"] {
            XCTAssertEqual(color(fenced, in: text, format: .markdown), .comment)
        }
    }
}
