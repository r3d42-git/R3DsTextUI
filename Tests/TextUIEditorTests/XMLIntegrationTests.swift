import AppKit
import WebKit
import XCTest
import TextUICore
@testable import TextUI

final class XMLIntegrationTests: XCTestCase {
    @MainActor
    func testXMLPreviewRoutingCollapseErrorsAndTabSwitchPreserveSource() async throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        delegate.store = SessionStore(url: directory.appendingPathComponent("Session.json"))
        delegate.buildWindow(restoreFrame: false)
        defer {
            delegate.checkpoint?.cancel()
            delegate.window.close()
            try? FileManager.default.removeItem(at: directory)
        }
        let source = "<root title='Grüße 😀'><child>Text &amp; mehr</child><script>alert(1)</script></root>"
        let draft = Draft(url: directory.appendingPathComponent("sample.XML"), file: TextFile(text: source))
        delegate.add(draft)
        XCTAssertTrue(delegate.previewButton.isEnabled)
        delegate.togglePreview()
        XCTAssertFalse(delegate.previewHost.isHidden)
        XCTAssertEqual(delegate.previewNote.stringValue, "XML · Offline-Vorschau")
        try await waitForBody("XML · Gültig", in: delegate.webView)
        let structure = try await evaluate("({elements:document.querySelectorAll('details').length, scripts:document.querySelectorAll('script').length, copyControls:document.querySelectorAll('[data-textui-copy-control]').length, text:document.body.textContent})", in: delegate.webView) as? [String: Any]
        XCTAssertGreaterThan(structure?["elements"] as? Int ?? 0, 0)
        XCTAssertEqual(structure?["scripts"] as? Int, 0)
        XCTAssertEqual(structure?["copyControls"] as? Int, 0, "The XML tree must remain readable without a copy button on every node")
        XCTAssertTrue((structure?["text"] as? String)?.contains("Text & mehr") == true)
        let collapsed = try await evaluate("(() => { const d=document.querySelector('details'); d.open=true; d.querySelector('summary').click(); return d.open; })()", in: delegate.webView)
        XCTAssertEqual(collapsed as? Bool, false)
        XCTAssertEqual(delegate.current?.editor.textView.string, source)
        XCTAssertEqual(delegate.current?.draft.file.text, source)

        delegate.current?.editor.textView.string = "<root>\n<broken></root>"
        delegate.updatePreview()
        try await waitForBody("XML-Vorschau nicht verfügbar", in: delegate.webView)
        let error = try await evaluate("document.body.textContent", in: delegate.webView) as? String
        XCTAssertTrue(error?.contains("Zeile 2") == true)
        XCTAssertTrue(error?.contains("Spalte") == true)
        XCTAssertEqual(delegate.current?.editor.textView.string, "<root>\n<broken></root>")
        delegate.add(Draft(file: TextFile(text: "Normale Notiz")))
        XCTAssertTrue(delegate.previewHost.isHidden)
        XCTAssertFalse(delegate.previewButton.isEnabled)
        delegate.select(draft.id)
        try await waitForBody("XML-Vorschau nicht verfügbar", in: delegate.webView)
        XCTAssertFalse(delegate.previewHost.isHidden)
    }

    @MainActor
    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { continuation.resume(with: $0) }
        }
    }

    @MainActor
    private func waitForBody(_ text: String, in webView: WKWebView) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let body = try? await evaluate("document.body ? document.body.textContent : ''", in: webView) as? String,
               body.contains(text), !webView.isLoading { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Preview did not display \(text)")
    }
}
