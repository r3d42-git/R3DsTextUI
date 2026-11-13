import Foundation
import XCTest
@testable import TextUICore

final class ScriptSyntaxTests: XCTestCase {
    private func color(_ needle: String, in text: String, spans: [SyntaxSpan]) -> SyntaxKind? {
        let range = (text as NSString).range(of: needle)
        XCTAssertNotEqual(range.location, NSNotFound, needle)
        return spans.last { NSLocationInRange(range.location, $0.range) }?.kind
    }

    private func assertDisjointAndBounded(_ spans: [SyntaxSpan], in text: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        var end = 0
        for span in spans {
            XCTAssertGreaterThanOrEqual(span.range.location, end, file: file, line: line)
            XCTAssertGreaterThan(span.range.length, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(NSMaxRange(span.range), (text as NSString).length, file: file, line: line)
            XCTAssertNotNil(Range(span.range, in: text), file: file, line: line)
            end = NSMaxRange(span.range)
        }
    }

    func testShellCommentsRespectWordsEscapesAndParameterExpansion() {
        let text = "#!/bin/zsh\r\necho foo#bar \\#literal ${name#prefix} ${name##prefix} # if 42 '$HOME'\r\nif true; then\r\n export COUNT=4\r\nfi"
        let spans = ScriptSyntax.shell(text)
        XCTAssertEqual(color("#!/bin", in: text, spans: spans), .comment)
        XCTAssertNil(color("foo#bar", in: text, spans: spans))
        XCTAssertNil(color("#literal", in: text, spans: spans))
        XCTAssertEqual(color("name#prefix", in: text, spans: spans), .attribute)
        XCTAssertEqual(color("name##prefix", in: text, spans: spans), .attribute)
        XCTAssertEqual(color("if 42", in: text, spans: spans), .comment)
        XCTAssertEqual(color("if true", in: text, spans: spans), .keyword)
        XCTAssertEqual(color("export", in: text, spans: spans), .keyword)
        assertDisjointAndBounded(spans, in: text)
    }

    func testShellQuotedAndSubstitutedRegionsAreOpaque() {
        let text = #"echo 'if $HOME # literal' "escaped \" # done" $HOME ${file%.txt} $(echo "$(date)"; (pwd)) 42 file42"#
        let spans = ScriptSyntax.shell(text)
        XCTAssertEqual(color("if $HOME", in: text, spans: spans), .string)
        XCTAssertEqual(color("# done", in: text, spans: spans), .string)
        XCTAssertEqual(color("$HOME ${", in: text, spans: spans), .attribute)
        XCTAssertEqual(color("file%.txt", in: text, spans: spans), .attribute)
        XCTAssertEqual(color("date", in: text, spans: spans), .attribute)
        XCTAssertEqual(color("42 file", in: text, spans: spans), .number)
        XCTAssertNil(color("file42", in: text, spans: spans))
        assertDisjointAndBounded(spans, in: text)
    }

    func testShellUnicodeCRLFAndUnfinishedRegions() {
        let text = "😀\r\nif true; then\r\n echo 'Grüße 👋 # if\r\n42"
        let spans = ScriptSyntax.shell(text)
        XCTAssertEqual(spans.first?.range, (text as NSString).range(of: "if"))
        XCTAssertEqual(color("42", in: text, spans: spans), .string)
        assertDisjointAndBounded(spans, in: text)
        let incomplete = "echo ${value#unfinished"
        XCTAssertEqual(ScriptSyntax.shell(incomplete).last?.range,
                       (incomplete as NSString).range(of: "${value#unfinished"))
    }

    func testPythonKeywordsDefinitionsAndNumericForms() {
        let text = "async def größe(x):\r\n await work(x)\r\nclass Gerät:\r\n pass\r\nmatch x:\r\n case None: return -0xFF_FF + 1_000.25e-3 + .5j\r\nname42 = 0b1010"
        let spans = ScriptSyntax.python(text)
        for word in ["async", "def", "await", "class", "pass", "match", "case", "None", "return"] {
            XCTAssertEqual(color(word, in: text, spans: spans), .keyword, word)
        }
        for word in ["größe", "Gerät"] { XCTAssertEqual(color(word, in: text, spans: spans), .tag) }
        for word in ["-0xFF_FF", "1_000.25e-3", ".5j", "0b1010"] {
            let span = spans.first { $0.range == (text as NSString).range(of: word) }
            XCTAssertEqual(span?.kind, .number, word)
        }
        XCTAssertNil(color("name42", in: text, spans: spans))
        assertDisjointAndBounded(spans, in: text)
    }

    func testPythonPrefixesTripleQuotesAndCommentPriority() {
        let text = "😀\r\nmessage = rf\"\"\"Grüße {await x}\r\n# def fake(): 123\r\n\"\"\"\r\nraw = r'it\\\'s # literal'\r\ndata = b'bytes'\r\n# f\"string\" class Fake\r\nreturn True"
        let spans = ScriptSyntax.python(text)
        for word in ["await x", "def fake", "123", "# literal", "bytes"] {
            XCTAssertEqual(color(word, in: text, spans: spans), .string, word)
        }
        XCTAssertEqual(color("class Fake", in: text, spans: spans), .comment)
        XCTAssertEqual(color("return", in: text, spans: spans), .keyword)
        assertDisjointAndBounded(spans, in: text)
    }

    func testPythonUnfinishedSingleLineRecoversAtNewlineAndTripleConsumesRemainder() {
        let text = "x = 'unfinished\r\nreturn 42\r\ny = f\"\"\"unfinished\r\n# comment 123"
        let spans = ScriptSyntax.python(text)
        XCTAssertEqual(color("unfinished", in: text, spans: spans), .string)
        XCTAssertEqual(color("return", in: text, spans: spans), .keyword)
        XCTAssertEqual(color("42", in: text, spans: spans), .number)
        XCTAssertEqual(color("# comment", in: text, spans: spans), .string)
        assertDisjointAndBounded(spans, in: text)
    }

    func testLargeIncompleteStringsAndSubstitutionsProduceOneOpaqueSpan() {
        let body = String(repeating: "😀 # if 123 \\\\" , count: 20_000)
        for (text, spans) in [
            ("'''" + body, ScriptSyntax.python("'''" + body)),
            ("'" + body, ScriptSyntax.shell("'" + body)),
            ("$(" + body, ScriptSyntax.shell("$(" + body))
        ] {
            XCTAssertEqual(spans.count, 1)
            XCTAssertEqual(spans.first?.range, NSRange(location: 0, length: (text as NSString).length))
            assertDisjointAndBounded(spans, in: text)
        }
    }
}
