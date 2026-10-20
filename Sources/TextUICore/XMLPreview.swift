import Foundation

/// An inert, offline view of the parsed XML structure. The editor's source is never rewritten.
public enum XMLPreview {
    public static func html(from source: String) -> String {
        let failure: (String) -> String = { message in
            MarkdownPreview.document(body: "<h2>XML-Vorschau nicht verfügbar</h2><p>\(xmlEscape(message))</p><p>Der Quelltext lässt sich weiterhin bearbeiten und speichern.</p>")
        }
        guard source.utf8.count <= 4 * 1_024 * 1_024 else {
            return failure("Zeile 1, Spalte 1: Das Dokument ist für die Vorschau zu groß (maximal 4 MiB).")
        }
        if let position = prohibitedDeclaration(in: source) {
            let prefix = source[..<position].replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
            return failure("Zeile \(lines.count), Spalte \((lines.last?.count ?? 0) + 1): DTDs und Entitätsdeklarationen sind in der Vorschau aus Sicherheitsgründen deaktiviert.")
        }

        // The caller has already decoded the file. Remove only the transport encoding
        // attribute from the declaration before supplying UTF-8 bytes to XMLParser.
        // Spaces and retained newlines preserve source locations.
        var input = source
        // Normalize only a syntactically valid declaration. Removing an encoding
        // attribute from an invalid declaration could otherwise hide its error.
        let declarationPattern = #"\A\uFEFF?<\?xml[ \t\r\n]+version[ \t\r\n]*=[ \t\r\n]*(?:"1\.[0-9]+"|'1\.[0-9]+')[ \t\r\n]+encoding[ \t\r\n]*=[ \t\r\n]*(?:"[A-Za-z][A-Za-z0-9._-]*"|'[A-Za-z][A-Za-z0-9._-]*')(?:[ \t\r\n]+standalone[ \t\r\n]*=[ \t\r\n]*(?:"(?:yes|no)"|'(?:yes|no)'))?[ \t\r\n]*\?>"#
        if let declaration = input.range(of: declarationPattern, options: .regularExpression),
           let encoding = input.range(of: #"\s+encoding\s*=\s*(?:"[^"<>]*"|'[^'<>]*')"#, options: .regularExpression, range: declaration) {
            input.replaceSubrange(encoding, with: input[encoding].map { $0.isNewline ? String($0) : " " }.joined())
        }
        let parser = XMLParser(data: Data(input.utf8))
        parser.shouldProcessNamespaces = false // Retain qualified names and xmlns attributes.
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        let renderer = XMLStructureRenderer()
        parser.delegate = renderer
        let valid = parser.parse()
        guard valid, parser.parserError == nil, renderer.error == nil else {
            return failure(renderer.error ?? "Zeile \(max(1, parser.lineNumber)), Spalte \(max(1, parser.columnNumber)): Das XML-Dokument ist nicht wohlgeformt. Bitte prüfe Elemente, Attribute und Entitätsreferenzen.")
        }
        return MarkdownPreview.document(body: """
        <style>.xml-tree { font: .88em/1.55 Menlo,monospace; } .xml-tree details { margin:.3em 0 .3em 1em; border-left:1px solid var(--line); padding-left:.6em; } .xml-tree>details { margin-left:0; } .xml-tree summary { cursor:pointer; color:var(--accent); } .xml-tree .xml-value { white-space:pre-wrap; margin:.3em 0; padding:.4em .6em; border-radius:5px; background:var(--code); } .xml-tree .xml-close,.xml-tree .xml-comment { color:var(--muted); }</style>
        <p>XML · Gültig</p><div class="xml-tree">\(renderer.output)</div>
        """)
    }

    /// Scan markup lexically: declaration-like text inside comments, CDATA and
    /// processing instructions is content, not a DTD. Never hand an actual DTD to libxml.
    private static func prohibitedDeclaration(in source: String) -> String.Index? {
        var cursor = source.startIndex
        while cursor < source.endIndex, let opening = source[cursor...].firstIndex(of: "<") {
            let tail = source[opening...]
            let terminator: String?
            if tail.hasPrefix("<!--") { terminator = "-->" }
            else if tail.hasPrefix("<![CDATA[") { terminator = "]]>" }
            else if tail.hasPrefix("<?") { terminator = "?>" }
            else if tail.hasPrefix("<!DOCTYPE") || tail.hasPrefix("<!ENTITY") { return opening }
            else { terminator = nil }
            if let terminator {
                guard let end = source.range(of: terminator, range: opening..<source.endIndex) else { return nil }
                cursor = end.upperBound
            } else {
                cursor = source.index(after: opening)
            }
        }
        return nil
    }
}

private func xmlEscape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

private final class XMLStructureRenderer: NSObject, XMLParserDelegate {
    var output = ""
    var error: String?
    private var names: [String] = []
    private var text = ""
    private var events = 0
    private var outputBytes = 0

    private func stop(_ parser: XMLParser, _ reason: String) {
        guard error == nil else { return }
        error = "Zeile \(max(1, parser.lineNumber)), Spalte \(max(1, parser.columnNumber)): \(reason)"
        parser.abortParsing()
    }

    private func append(_ html: String, parser: XMLParser) {
        guard error == nil else { return }
        events += 1
        outputBytes += html.utf8.count
        guard events <= 50_000, outputBytes <= 16 * 1_024 * 1_024 else {
            stop(parser, "Die Struktur ist für die Vorschau zu umfangreich."); return
        }
        output += html
    }

    private func flush(_ parser: XMLParser) {
        guard !text.isEmpty else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Keep whitespace in the DOM without empty code boxes for source indentation.
            append("<span class=\"xml-whitespace\">\(xmlEscape(text))</span>", parser: parser)
        } else {
            append("<div class=\"xml-value xml-text\">\(xmlEscape(text))</div>", parser: parser)
        }
        text = ""
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard error == nil else { return }
        flush(parser)
        guard names.count < 128 else { stop(parser, "Die Verschachtelung ist für die Vorschau zu tief (maximal 128 Ebenen)."); return }
        // XML quoting and HTML quoting are separate: the visible label must still
        // distinguish literal quotation marks from attribute delimiters.
        let attributeText = attributes.keys.sorted().map { key in
            let value = attributes[key]!.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "\t", with: "&#9;")
                .replacingOccurrences(of: "\n", with: "&#10;")
                .replacingOccurrences(of: "\r", with: "&#13;")
            return " \(key)=\"\(value)\""
        }.joined()
        append("<details\(names.count < 3 ? " open" : "")><summary>\(xmlEscape("<" + name + attributeText + ">"))</summary>", parser: parser)
        names.append(name)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard error == nil else { return }
        flush(parser)
        append("<div class=\"xml-close\">\(xmlEscape("</" + name + ">"))</div></details>", parser: parser)
        if !names.isEmpty { names.removeLast() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { if error == nil { text += string } }
    func parser(_ parser: XMLParser, foundIgnorableWhitespace whitespaceString: String) { if error == nil { text += whitespaceString } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        flush(parser)
        append("<div class=\"xml-value xml-cdata\">\(xmlEscape("<![CDATA[" + String(decoding: CDATABlock, as: UTF8.self) + "]]>"))</div>", parser: parser)
    }
    func parser(_ parser: XMLParser, foundComment comment: String) {
        flush(parser)
        append("<div class=\"xml-value xml-comment\">\(xmlEscape("<!--" + comment + "-->"))</div>", parser: parser)
    }
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
        flush(parser)
        append("<div class=\"xml-value xml-instruction\">\(xmlEscape("<?" + target + (data.map { " " + $0 } ?? "") + "?>"))</div>", parser: parser)
    }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        stop(parser, "Externe Entitäten sind in der Vorschau deaktiviert.")
        return nil
    }
}
