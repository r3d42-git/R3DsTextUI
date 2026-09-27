import XCTest
@testable import TextUICore

final class MarkdownPreviewTests: XCTestCase {
    func testHeadingsNestedFormattingListsAndQuotes() {
        let html = MarkdownPreview.html(from: """
        # Heading **bold** & more

        - First
          - Nested *emphasis*

        3. Third

        > A ~~removed~~ quote
        """)
        XCTAssertTrue(html.contains("<h1>Heading <strong>bold</strong> &amp; more</h1>"))
        XCTAssertTrue(html.contains("<ul><li><p>First</p><ul>"))
        XCTAssertTrue(html.contains("<em>emphasis</em>"))
        XCTAssertTrue(html.contains("<ol start=\"3\">"))
        XCTAssertTrue(html.contains("<blockquote><p>A <del>removed</del> quote</p></blockquote>"))
    }

    func testTablesAlignmentAndTaskLists() {
        let html = MarkdownPreview.html(from: """
        | Name | Value |
        | :--- | ---: |
        | **A** | 42 |

        - [x] Done
        - [ ] Pending
        """)
        XCTAssertTrue(html.contains("<th align=\"left\">Name</th>"))
        XCTAssertTrue(html.contains("<td align=\"right\">42</td>"))
        XCTAssertTrue(html.contains("<strong>A</strong>"))
        XCTAssertTrue(html.contains("type=\"checkbox\" disabled checked>"))
        XCTAssertTrue(html.contains("type=\"checkbox\" disabled>"))
    }

    func testCodeIsEscapedButAuthoredHTMLIsPreserved() {
        let html = MarkdownPreview.html(from: """
        `<b>inline & code</b>`

        ```html
        <script>alert("text")</script>
        ```

        <div class="warning"><strong>Raw HTML</strong></div>

        An <em>inline HTML</em> example.
        """)
        XCTAssertTrue(html.contains("<code>&lt;b&gt;inline &amp; code&lt;/b&gt;</code>"))
        XCTAssertTrue(html.contains("<pre><code class=\"language-html\">&lt;script&gt;alert(&quot;text&quot;)&lt;/script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("<div class=\"warning\"><strong>Raw HTML</strong></div>"))
        XCTAssertTrue(html.contains("An <em>inline HTML</em> example."))
    }

    func testLinksAndImageAttributesAreEscaped() {
        let html = MarkdownPreview.html(from: """
        [A & B](https://example.com/?a=1&b=2 "A &quot;title&quot;")

        ![An & image](image.png "Image title")
        """)
        XCTAssertTrue(html.contains("href=\"https://example.com/?a=1&amp;b=2\""))
        XCTAssertTrue(html.contains("title=\"A &quot;title&quot;\""))
        XCTAssertTrue(html.contains(">A &amp; B</a>"))
        XCTAssertTrue(html.contains("alt=\"An &amp; image\""))
    }

    func testEmptyDocumentHasOfflineResponsiveShell() {
        let html = MarkdownPreview.html(from: "")
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("prefers-color-scheme:dark"))
        XCTAssertTrue(html.contains("<main></main>"))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("<link"))
    }
}
