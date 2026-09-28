import Foundation
import XCTest
@testable import TextUICore

final class JSONPreviewTests: XCTestCase {
    func testFormattingPreservesExactValuesAndDuplicateKeys() throws {
        let source = #"{"z":9007199254740993123456789,"a":1.2300e+400,"z":"\u0041","list":[true,false,null,{},[]]}"#
        let formatted = try JSONPreview.formatted(source)
        XCTAssertEqual(formatted, """
        {
          "z": 9007199254740993123456789,
          "a": 1.2300e+400,
          "z": "\\u0041",
          "list": [
            true,
            false,
            null,
            {},
            []
          ]
        }
        """)
        XCTAssertEqual(try JSONPreview.formatted(formatted), formatted)
    }

    func testScalarsAndUnicode() throws {
        for source in ["true", "false", "null", "-0", "1.2e-3", #""Grüße 👩🏽‍💻 \" \\ \n""#, "[]", "{}"] {
            XCTAssertEqual(try JSONPreview.formatted(" \r\n" + source + "\t"), source)
        }
    }

    func testInvalidJSONAndLocation() {
        for source in ["", "{", "[1,]", #"{"a":1,}"#, "01", "-01", "+1", "1.", "1e", "NaN", "true false", "// comment\n{}", #"{"a" 1}"#, #""\x""#, #""\u12GG""#, "\"a\nb\"", "\"open"] {
            XCTAssertThrowsError(try JSONPreview.formatted(source), source)
        }
        XCTAssertThrowsError(try JSONPreview.formatted("{\r\n  \"😀\": }")) { error in
            XCTAssertTrue(error.localizedDescription.contains("Zeile 2, Spalte 8"), error.localizedDescription)
        }
        XCTAssertThrowsError(try JSONPreview.formatted(String(repeating: "[", count: 300)))
    }

    func testHTMLIsEscapedAndErrorsReplacePreview() {
        let html = JSONPreview.html(from: #"{"html":"</code><script>alert(1)</script>&"}"#)
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("JSON · Gültig"))
        let invalid = JSONPreview.html(from: "{")
        XCTAssertTrue(invalid.contains("JSON-Vorschau nicht verfügbar"))
        XCTAssertFalse(invalid.contains("JSON · Gültig"))
    }

    func testSyntaxStringsDoNotLeakTokensAndUseUTF16Ranges() {
        let source = #"{"😀": "true 42 { \"x\"", "flag": false, "n": -2.5e+10}"#
        let spans = SyntaxHighlighting.spans(in: source, format: .json)
        let ns = source as NSString
        XCTAssertEqual(spans.filter { $0.kind == .attribute }.map { ns.substring(with: $0.range) }, [#""😀""#, #""flag""#, #""n""#])
        XCTAssertEqual(spans.filter { $0.kind == .keyword }.map { ns.substring(with: $0.range) }, ["false"])
        XCTAssertEqual(spans.filter { $0.kind == .number }.map { ns.substring(with: $0.range) }, ["-2.5e+10"])
        XCTAssertEqual(spans.filter { $0.kind == .string }.count, 1)
    }

    func testOpenEditSaveAndRestoreJSONWithoutReformatting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sample.JSON")
        let file = TextFile(text: "{\r\n\t\"a\": 1\r\n}", encoding: String.Encoding.utf16LittleEndian.rawValue, bom: true)
        try file.data().write(to: url)
        var draft = try Draft.open(url)
        XCTAssertEqual(draft.format, .json)
        _ = JSONPreview.html(from: draft.file.text)
        XCTAssertFalse(draft.isDirty)
        try draft.save(to: url)
        XCTAssertEqual(try Data(contentsOf: url), try file.data())
        draft.file.text = "{\r\n\t\"a\": " // Incomplete edits remain saveable and recoverable.
        let store = SessionStore(url: directory.appendingPathComponent("session.json"))
        try store.save(Session(drafts: [draft], selected: draft.id))
        let restored = try XCTUnwrap(store.load()?.drafts.first)
        XCTAssertEqual(restored.format, .json)
        XCTAssertEqual(restored.file, draft.file)
        XCTAssertTrue(restored.isDirty)
        try draft.save(to: url)
        XCTAssertEqual(try Draft.open(url).file, draft.file)
    }
}
