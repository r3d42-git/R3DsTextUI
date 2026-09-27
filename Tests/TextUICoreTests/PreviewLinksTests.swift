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
        XCTAssertTrue(PreviewLinks.isDocumentAnchor(try XCTUnwrap(URL(string: "about:blank#section"))))
        for text in ["https://example.com/#section", "about:blank", "about:other#section"] {
            XCTAssertFalse(PreviewLinks.isDocumentAnchor(try XCTUnwrap(URL(string: text))))
        }
    }
}
