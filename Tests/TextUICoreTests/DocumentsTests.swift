import Foundation
import XCTest
@testable import TextUICore

final class DocumentsTests: XCTestCase {
    func testDokuWikiTextDetectionPreservesFileAndSession() throws {
        let source = "====== Anleitung ======\r\n\r\n[[https://example.com|Beispiel]]\r\n<code>echo Hallo</code>\r\n"
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("Anleitung.txt")
        let data = try TextFile(text: source, encoding: String.Encoding.utf16LittleEndian.rawValue, bom: true).data()
        try data.write(to: url)
        var draft = try Draft.open(url)
        XCTAssertEqual(draft.format, .dokuwiki)
        XCTAssertFalse(draft.isDirty)
        let restored = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(Session(drafts: [draft], selected: draft.id)))
        XCTAssertEqual(restored.drafts.first?.format, .dokuwiki)
        try draft.save(to: url)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertEqual(draft.url?.pathExtension, "txt")
        XCTAssertEqual(DocumentFormat(url: directory.appendingPathComponent("explicit.md"), text: source), .markdown)
        XCTAssertEqual(DocumentFormat(url: directory.appendingPathComponent("explicit.html"), text: source), .html)
        XCTAssertEqual(DocumentFormat(url: directory.appendingPathComponent("plain.txt"), text: "Normaler Text mit **Sternchen**."), .text)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testUnicodeAndCRLFRoundTripPreservesExactBytesForSupportedEncodings() throws {
        let text = "Grüße 👩🏽‍💻\r\n日本語 e\u{301}\r\n"
        for (encoding, prefix) in [(String.Encoding.utf8, [UInt8]()), (.utf8, [0xEF, 0xBB, 0xBF]), (.utf16LittleEndian, [0xFF, 0xFE]), (.utf16BigEndian, [0xFE, 0xFF])] {
            var original = Data(prefix)
            original.append(try XCTUnwrap(text.data(using: encoding)))
            let file = try TextFile.decode(original)
            XCTAssertEqual(file.text, text)
            XCTAssertEqual(file.encoding, encoding.rawValue)
            XCTAssertEqual(file.bom, !prefix.isEmpty)
            XCTAssertEqual(file.lineEnding, "CRLF")
            XCTAssertEqual(file.newline, "\r\n")
            XCTAssertEqual(try file.data(), original)
        }
    }

    func testInvalidUTF8AndBinaryContentAreRejected() {
        for data in [Data([0xFF]), Data([0x61, 0, 0x62])] {
            XCTAssertThrowsError(try TextFile.decode(data)) { error in
                guard case EditorError.unsupportedEncoding = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testSaveUpdatesBaselineAndKeepsLineEndings() throws {
        let url = try temporaryDirectory().appendingPathComponent("example.MD")
        try Data("Original\r\n".utf8).write(to: url)
        var draft = try Draft.open(url)
        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(draft.format, .markdown)
        draft.file.text += "Änderung 😀\r\n"
        XCTAssertTrue(draft.isDirty)
        try draft.save(to: url)
        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(try Data(contentsOf: url), Data("Original\r\nÄnderung 😀\r\n".utf8))
    }

    func testExternalModificationCannotBeOverwritten() throws {
        let url = try temporaryDirectory().appendingPathComponent("file.txt")
        try Data("Original".utf8).write(to: url)
        var draft = try Draft.open(url)
        draft.file.text = "My changes"
        let external = Data("External changes".utf8)
        try external.write(to: url)
        XCTAssertThrowsError(try draft.save(to: url)) { error in
            guard case EditorError.externalChange = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: url), external)
        XCTAssertTrue(draft.isDirty)
        XCTAssertEqual(draft.file.text, "My changes")
    }

    func testExternalDeletionRequiresSaveAs() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("file.txt")
        try Data("Original".utf8).write(to: url)
        var draft = try Draft.open(url)
        draft.file.text = "Kept draft"
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try draft.save(to: url)) { error in
            guard case EditorError.externalChange = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let replacement = directory.appendingPathComponent("recovered.html")
        try draft.save(to: replacement)
        XCTAssertEqual(try String(contentsOf: replacement, encoding: .utf8), "Kept draft")
        XCTAssertEqual(draft.format, .html)
        XCTAssertFalse(draft.isDirty)
    }

    func testSessionRestoresUnnamedAndEditedDraftsWithoutSavingDocuments() throws {
        let directory = try temporaryDirectory()
        let documentURL = directory.appendingPathComponent("notes.txt")
        let original = Data("Saved version".utf8)
        try original.write(to: documentURL)
        var edited = try Draft.open(documentURL)
        edited.file.text = "Unsaved version 😀"
        edited.selection = 8
        edited.scrollY = 420.5
        let unnamed = Draft(file: TextFile(text: "New draft"), selection: 4)
        let store = SessionStore(url: directory.appendingPathComponent("session/session.json"))
        XCTAssertNil(try store.load())
        try store.save(Session(drafts: [edited, unnamed], selected: unnamed.id))
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.selected, unnamed.id)
        XCTAssertEqual(restored.drafts.map(\.id), [edited.id, unnamed.id])
        XCTAssertEqual(restored.drafts[0].file, edited.file)
        XCTAssertEqual(restored.drafts[0].baseline, original)
        XCTAssertEqual(restored.drafts[0].selection, 8)
        XCTAssertEqual(restored.drafts[0].scrollY, 420.5)
        XCTAssertTrue(restored.drafts[0].isDirty)
        XCTAssertNil(restored.drafts[1].url)
        XCTAssertEqual(restored.drafts[1].file.text, "New draft")
        XCTAssertTrue(restored.drafts[1].isDirty)
        XCTAssertEqual(try Data(contentsOf: documentURL), original)
    }

    func testUnsupportedSessionVersionAndCorruptionAreNotSilentlyAccepted() throws {
        let url = try temporaryDirectory().appendingPathComponent("session.json")
        let store = SessionStore(url: url)
        var future = Session(drafts: [], selected: nil)
        future.version = 99
        try store.save(future)
        XCTAssertThrowsError(try store.load())
        let corrupted = Data("{broken".utf8)
        try corrupted.write(to: url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: url), corrupted)
    }
}
