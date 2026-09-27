import AppKit
import WebKit
import XCTest
@testable import TextUI

final class PreviewCodeCopyTests: XCTestCase {
    @MainActor
    func testCopyPreservesExactTextAndRejectsInvalidPayload() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let text = "  printf '<&> 🙂'\n\tsecond line\n"
        XCTAssertTrue(PreviewCodeCopy.copy(text, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), text)
        XCTAssertFalse(PreviewCodeCopy.copy(["text": text], to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), text)
        XCTAssertFalse(PreviewCodeCopy.copy(String(repeating: "x", count: PreviewCodeCopy.maximumCopyBytes + 1), to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), text)
    }

    @MainActor
    func testIsolatedControlsWorkWithPageScriptsDisabledWithoutChangingCode() async throws {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let copyControls = PreviewCodeCopy(configuration: config)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: config)
        let loaded = expectation(description: "Preview loaded")
        let navigation = NavigationObserver { loaded.fulfill() }
        webView.navigationDelegate = navigation
        webView.loadHTMLString("""
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'none'">
        <body><pre><code>  &lt;tag&gt; &amp; 🙂
        \tline two
        </code></pre><p>Inline <code>x &lt; y</code>.</p>
        <script>document.body.dataset.documentScriptRan = 'yes';</script></body>
        """, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 10)
        let script = """
        ({ count: document.querySelectorAll('[data-textui-copy-control]').length,
           block: document.querySelector('pre').textContent,
           inline: document.querySelector('p code').textContent,
           documentScriptRan: document.body.dataset.documentScriptRan || 'no' })
        """
        let value: Any = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
                continuation.resume(with: result)
            }
        }
        let result = value as? [String: Any]
        XCTAssertEqual(result?["count"] as? Int, 2)
        XCTAssertEqual(result?["block"] as? String, "  <tag> & 🙂\n\tline two\n")
        XCTAssertEqual(result?["inline"] as? String, "x < y")
        XCTAssertEqual(result?["documentScriptRan"] as? String, "no")
        withExtendedLifetime(copyControls) {}
    }
}

@MainActor
private final class NavigationObserver: NSObject, WKNavigationDelegate {
    private let loaded: () -> Void
    init(loaded: @escaping () -> Void) { self.loaded = loaded }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded() }
}
