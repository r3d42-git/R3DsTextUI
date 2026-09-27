import XCTest
@testable import TextUICore

final class PreviewLinksTests: XCTestCase {
    func testOnlyWebLinksCanOpenInBrowser() throws {
        for text in ["https://example.com/path?q=one%20two#part", "http://example.org", "HTTPS://example.com"] {
            let url = try XCTUnwrap(URL(string: text))
            XCTAssertEqual(PreviewLinks.browserURL(url), url)
        }
        for text in ["file:///tmp/example.txt", "javascript:alert(1)", "data:text/html,test", "mailto:person@example.com", "textui:command", "https:///", "https://user:secret@example.com", "relative/page"] {
            let url = try XCTUnwrap(URL(string: text))
            XCTAssertNil(PreviewLinks.browserURL(url), text)
        }
    }

    func testAnchorsStayInOfflineDocument() throws {
        for fragment in ["section", "", "section?text", "caf%C3%A9"] {
            let url = try XCTUnwrap(URL(string: "https://textui-preview.invalid/#" + fragment))
            XCTAssertTrue(PreviewLinks.isDocumentAnchor(url), url.absoluteString)
            XCTAssertNil(PreviewLinks.browserURL(url))
        }
        for text in ["https://example.com/#section", "about:blank#section",
                     "https://textui-preview.invalid/", "https://other.invalid/#section",
                     "https://textui-preview.invalid/?query#section", "https://textui-preview.invalid/other#section",
                     "https://textui-preview.invalid:123/#section", "https://user@textui-preview.invalid/#section",
                     "https://textui-preview.invalid/%23section"] {
            XCTAssertFalse(PreviewLinks.isDocumentAnchor(try XCTUnwrap(URL(string: text))), text)
        }
    }
}
