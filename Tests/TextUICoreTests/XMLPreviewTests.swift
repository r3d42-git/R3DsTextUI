import Foundation
import XCTest
@testable import TextUICore

final class XMLPreviewTests: XCTestCase {
    func testQualifiedNamesAttributesAndCollapsibleStructure() {
        let html = XMLPreview.html(from: #"<ns:root xmlns:ns="urn:test" ns:id="42"><empty/><child>Grüße 👩🏽‍💻 日本語</child></ns:root>"#)
        XCTAssertTrue(html.contains("XML · Gültig"), html)
        XCTAssertEqual(html.components(separatedBy: "<details open>").count - 1, 3)
        XCTAssertTrue(html.contains("ns:root ns:id=&quot;42&quot; xmlns:ns=&quot;urn:test&quot;"))
        XCTAssertTrue(html.contains("&lt;/ns:root&gt;"))
        XCTAssertTrue(html.contains("Grüße 👩🏽‍💻 日本語"))
        XCTAssertTrue(html.contains("&lt;empty&gt;"))
    }

    func testMixedContentCDATACommentsAndInstructionsRetainOrder() throws {
        let html = XMLPreview.html(from: "<?xml-stylesheet type=\"text/xsl\" href=\"https://example.invalid/style.xsl\"?><p>vor <b>fett</b> nach<![CDATA[<raw>&😀]]><!-- Kommentar --><?local test?></p>")
        XCTAssertTrue(html.contains("XML · Gültig"), html)
        let fragments = ["&lt;?xml-stylesheet", "&lt;p&gt;", "vor ", "&lt;b&gt;", "fett", "&lt;/b&gt;", " nach", "&lt;![CDATA[&lt;raw&gt;&amp;😀]]&gt;", "&lt;!-- Kommentar --&gt;", "&lt;?local test?&gt;", "&lt;/p&gt;"]
        var position = html.startIndex
        for fragment in fragments {
            let range = try XCTUnwrap(html.range(of: fragment, range: position..<html.endIndex), fragment)
            position = range.upperBound
        }
        XCTAssertFalse(html.contains("<link"))
        XCTAssertFalse(html.contains("<script"))
    }

    func testHTMLAndAttributesAreInert() {
        let html = XMLPreview.html(from: #"<root onclick="alert(&quot;x&quot;)" src="file:///etc/passwd">&lt;/code&gt;&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot; '<![CDATA[<img src=x onerror=alert(1)>]]></root>"#)
        XCTAssertTrue(html.contains("XML · Gültig"), html)
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("onclick=&quot;alert(&amp;quot;x&amp;quot;)&quot;"))
        XCTAssertTrue(html.contains("&lt;img src=x onerror=alert(1)&gt;"))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("<img"))
        XCTAssertFalse(html.contains(" src=\"file:"))
    }

    func testMalformedDocumentsHaveGermanLocationsAndEditingHint() {
        for source in ["", "<root>", "<root>\n<child></root>", "<a/><b/>", "<a x='1' x='2'/>", "<a>&unknown;</a>", "<a><script></a>"] {
            let html = XMLPreview.html(from: source)
            XCTAssertTrue(html.contains("XML-Vorschau nicht verfügbar"), source)
            XCTAssertTrue(html.contains("Zeile "), source)
            XCTAssertTrue(html.contains("Spalte "), source)
            XCTAssertTrue(html.contains("weiterhin bearbeiten und speichern"), source)
            XCTAssertFalse(html.contains("XML · Gültig"), source)
            XCTAssertFalse(html.contains("<script>"), source)
        }
    }

    func testDTDAndEntityDeclarationsAreRejectedBeforeParsing() {
        for source in [
            #"<!DOCTYPE root SYSTEM "file:///etc/passwd"><root/>"#,
            #"<!DOCTYPE root SYSTEM "https://example.invalid/external.dtd"><root/>"#,
            #"<!DOCTYPE root [<!ENTITY secret SYSTEM "file:///etc/passwd">]><root>&secret;</root>"#,
            #"<!DOCTYPE root [<!ENTITY a "123"><!ENTITY b "&a;&a;">]><root>&b;</root>"#,
            #"<!ENTITY external SYSTEM "file:///etc/passwd"><root/>"#
        ] {
            let html = XMLPreview.html(from: source)
            XCTAssertTrue(html.contains("DTD"), source)
            XCTAssertTrue(html.contains("deaktiviert"), source)
            XCTAssertFalse(html.contains("XML · Gültig"), source)
        }
    }

    func testDeclarationTextInInertContentDoesNotTriggerDTDRejection() {
        let html = XMLPreview.html(from: #"<!-- <!DOCTYPE root> --><?test <!DOCTYPE root>?><root><![CDATA[<!DOCTYPE root [<!ENTITY test 'ok'>]>]]>&amp;&lt;&gt;&quot;&apos;&#x1F600;</root>"#)
        XCTAssertTrue(html.contains("XML · Gültig"), html)
        XCTAssertTrue(html.contains("&lt;!DOCTYPE root"))
        XCTAssertTrue(html.contains("😀"))
    }

    func testDecodedStringsIgnoreTransportEncodingDeclarations() {
        for encoding in ["UTF-16", "UTF-16LE", "ISO-8859-1", "windows-1252", "UTF-8"] {
            let source = "<?xml version=\"1.0\" encoding=\"\(encoding)\" standalone=\"yes\"?><root>Grüße € 😀<![CDATA[日本語]]></root>"
            let original = source
            let html = XMLPreview.html(from: source)
            XCTAssertTrue(html.contains("XML · Gültig"), "\(encoding): \(html)")
            XCTAssertTrue(html.contains("Grüße € 😀"), encoding)
            XCTAssertTrue(html.contains("日本語"), encoding)
            XCTAssertEqual(source, original)
        }
        XCTAssertTrue(XMLPreview.html(from: "\u{FEFF}<?xml version='1.0' encoding='UTF-16'?><root>ä</root>").contains("XML · Gültig"))
    }

    func testLimitsFailGracefully() {
        let deeplyNested = String(repeating: "<a>", count: 129) + String(repeating: "</a>", count: 129)
        XCTAssertTrue(XMLPreview.html(from: deeplyNested).contains("maximal 128 Ebenen"))
        let wide = "<root>" + String(repeating: "<a/>", count: 25_001) + "</root>"
        XCTAssertTrue(XMLPreview.html(from: wide).contains("zu umfangreich"))
        let large = "<root>" + String(repeating: "x", count: 4 * 1_024 * 1_024) + "</root>"
        XCTAssertTrue(XMLPreview.html(from: large).contains("maximal 4 MiB"))
    }

    func testInvalidEncodingDeclarationsAreNotSilentlyRepaired() {
        for declaration in [
            "<?xml encoding='UTF-8' version='1.0'?>",
            "<?xml version='1.0'encoding='UTF-8'?>",
            "<?xml version='1.0' encoding='not a name'?>",
            "<?xml version='1.0' encoding='UTF-8' encoding='UTF-8'?>"
        ] {
            XCTAssertTrue(XMLPreview.html(from: declaration + "<root/>").contains("XML-Vorschau nicht verfügbar"), declaration)
        }
    }
}
