import AppKit
import UniformTypeIdentifiers
import XCTest
import TextUICore
@testable import TextUI

final class ScriptIntegrationTests: XCTestCase {
    @MainActor
    func testScriptOpenEditSaveUndoAndPreviewSwitchDoNotExecuteDocuments() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let delegate = AppDelegate()
        delegate.store = SessionStore(url: directory.appendingPathComponent("Session.json"))
        delegate.buildWindow(restoreFrame: false)
        defer {
            delegate.checkpoint?.cancel(); delegate.refresh?.cancel(); delegate.invalidateSearch()
            delegate.sessionWriter.flush()
            delegate.window.delegate = nil; delegate.window.close()
            try? FileManager.default.removeItem(at: directory)
        }
        // If any document were ever executed, it would create this disposable marker.
        let marker = directory.appendingPathComponent("must-not-exist")
        let samples: [(String, String, DocumentFormat)] = [
            ("Automatische_Benachrichtigungseinstellungen_Grüße_👩🏽‍💻.command", "#!/bin/zsh\n# Grüße\nprintf test > '\(marker.path)'\n", .shell),
            ("Automatische_Benachrichtigungseinstellungen_Grüße_👩🏽‍💻.py", "from pathlib import Path\n# Grüße\nPath(\"\(marker.path)\").touch()\n", .python)
        ]
        delegate.add(Draft(url: directory.appendingPathComponent("preview.md"), file: TextFile(text: "# Markdown")))
        delegate.togglePreview()
        XCTAssertFalse(delegate.previewHost.isHidden)
        for (name, source, format) in samples {
            let url = directory.appendingPathComponent(name)
            try Data(source.utf8).write(to: url)
            delegate.open([url])
            let tab = try XCTUnwrap(delegate.current)
            XCTAssertEqual(tab.draft.format, format)
            XCTAssertTrue(delegate.status.stringValue.contains(format.rawValue))
            XCTAssertFalse(delegate.previewButton.isEnabled)
            XCTAssertTrue(delegate.previewHost.isHidden)
            let menu = NSMenuItem(title: "Vorschau", action: #selector(AppDelegate.togglePreview), keyEquivalent: "")
            XCTAssertFalse(delegate.validateMenuItem(menu))
            let text = tab.editor.textView
            text.insertText("# Änderung 😀\n", replacementRange: NSRange(location: source.utf16.count, length: 0))
            text.undoManager?.undo()
            XCTAssertEqual(text.string, source)
            text.undoManager?.redo()
            let edited = text.string
            XCTAssertNotEqual(edited, source)
            XCTAssertTrue(delegate.save(tab, saveAs: false))
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), edited)
            let deadline = Date().addingTimeInterval(3)
            while text.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil, Date() < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertNotNil(text.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil))
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        }
        let restored = try XCTUnwrap(delegate.store.load())
        XCTAssertEqual(restored.drafts.suffix(2).map(\.format), [.shell, .python])
        delegate.select(delegate.tabs[0].draft.id)
        XCTAssertTrue(delegate.previewButton.isEnabled)
        XCTAssertFalse(delegate.previewHost.isHidden)
        XCTAssertTrue(AppDelegate.openDocumentTypes.contains(.pythonScript))
        let command = try XCTUnwrap(UTType(filenameExtension: "command"))
        XCTAssertTrue(AppDelegate.openDocumentTypes.contains(command))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }
}
