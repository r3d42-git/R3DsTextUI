import Foundation
import XCTest
@testable import TextUICore

final class ScriptDocumentTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testExtensionsTakePrecedenceOverDokuWikiContentAndDoNotOfferPreview() {
        let wiki = "====== Title ======\n[[https://example.com|Example]]\n<code>example</code>"
        for ext in ["command", "COMMAND", "py", "PY"] {
            let format = DocumentFormat(url: URL(fileURLWithPath: "/synthetic/example.\(ext)"), text: wiki)
            XCTAssertEqual(format, ext.lowercased() == "py" ? .python : .shell)
            XCTAssertFalse(format.supportsPreview)
            XCTAssertTrue(TextNavigation.outline(wiki, format: format).isEmpty)
        }
        for format in [DocumentFormat.markdown, .html, .json, .xml, .dokuwiki] { XCTAssertTrue(format.supportsPreview) }
        XCTAssertFalse(DocumentFormat.text.supportsPreview)
    }

    func testScriptRoundTripPreservesBOMEncodingNewlinesAndIncompleteEdits() throws {
        let directory = try directory()
        for ext in ["command", "py"] {
            let source = ext == "command" ? "#!/bin/zsh\r\n# Grüße 👩🏽‍💻\r\necho \"日本語\"\r\n" : "#!/usr/bin/env python3\r\n# Grüße 👩🏽‍💻\r\nprint('日本語')\r\n"
            for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
                let file = TextFile(text: source, encoding: encoding.rawValue, bom: true)
                let original = try file.data()
                let url = directory.appendingPathComponent("script.\(ext)")
                try original.write(to: url)
                var draft = try Draft.open(url)
                XCTAssertEqual(draft.format, ext == "py" ? .python : .shell)
                XCTAssertFalse(draft.isDirty)
                try draft.save(to: url)
                XCTAssertEqual(try Data(contentsOf: url), original)
                draft.file.text += ext == "py" ? "def unfinished(" : "echo \"unfinished"
                let store = SessionStore(url: directory.appendingPathComponent("session.json"))
                try store.save(Session(drafts: [draft], selected: draft.id))
                let restored = try XCTUnwrap(store.load()?.drafts.first)
                XCTAssertEqual(restored.file, draft.file)
                XCTAssertEqual(restored.format, draft.format)
                XCTAssertTrue(restored.isDirty)
                try draft.save(to: url)
                XCTAssertEqual(try Draft.open(url).file, restored.file)
            }
        }
    }

    func testSavingScriptsPreservesExistingExecutePermissionsAndDoesNotAddThem() throws {
        let directory = try directory()
        for ext in ["command", "py"] {
            for permissions in [0o644, 0o755] {
                let url = directory.appendingPathComponent("script-\(permissions).\(ext)")
                try Data("# original\n".utf8).write(to: url)
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
                var draft = try Draft.open(url)
                draft.file.text += "# edited\n"
                try draft.save(to: url)
                XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, permissions)
            }
            var fresh = Draft(file: TextFile(text: "# new script\n"))
            let destination = directory.appendingPathComponent("new-script.\(ext)")
            try fresh.save(to: destination)
            XCTAssertEqual(fresh.format, ext == "py" ? .python : .shell)
            let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? Int)
            XCTAssertEqual(mode & 0o111, 0, "Saving a new script must not add execute permissions")
        }
    }

    func testFinderRegistrationKeepsEditorAsAlternateHandler() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("Resources/Info.plist")), format: nil) as? [String: Any]
        let types = try XCTUnwrap(plist?["CFBundleDocumentTypes"] as? [[String: Any]])
        for ext in ["command", "py"] {
            let handler = try XCTUnwrap(types.first { ($0["CFBundleTypeExtensions"] as? [String])?.contains(ext) == true })
            XCTAssertEqual(handler["CFBundleTypeRole"] as? String, "Editor")
            XCTAssertEqual(handler["LSHandlerRank"] as? String, "Alternate")
        }
    }
}
