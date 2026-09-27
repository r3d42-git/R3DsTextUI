import Foundation

public enum SyntaxKind: Sendable {
    case tag, attribute, string, number, keyword, selector, comment, punctuation, heading, strong
}

public struct SyntaxSpan: Sendable {
    public let range: NSRange
    public let kind: SyntaxKind
    public init(range: NSRange, kind: SyntaxKind) { self.range = range; self.kind = kind }
}

/// Lightweight display tokens, expressed in NSTextView's UTF-16 coordinates.
/// Later spans take precedence. This intentionally does not validate source code.
public enum SyntaxHighlighting {
    public static func spans(in text: String, format: DocumentFormat) -> [SyntaxSpan] {
        switch format {
        case .text: return []
        case .markdown: return markdown(text)
        case .dokuwiki: return DokuWikiSyntax.spans(in: text)
        case .html: return html(text)
        }
    }

    private static func matches(_ pattern: String, in text: String, range: NSRange? = nil) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: text, range: range ?? NSRange(location: 0, length: (text as NSString).length))
    }

    private static func markdown(_ text: String) -> [SyntaxSpan] {
        let rules: [(String, SyntaxKind)] = [
            (#"(?m)^ {0,3}#{1,6}[\t ].*$"#, .heading),
            (#"\[[^\]\r\n]+\]\([^\)\r\n]+\)"#, .selector),
            (#"(?m)(\*\*|__)[^\r\n]+?\1"#, .strong),
            (#"`[^`\r\n]+`"#, .string),
            (#"(?ms)^ {0,3}```[^\r\n]*\r?\n.*?(?:^ {0,3}```[^\r\n]*|\z)"#, .comment)
        ]
        // Embedded HTML uses the same palette as HTML documents. Markdown code
        // spans and fences come last so literal examples retain their code color.
        return html(text) + rules.flatMap { pattern, kind in matches(pattern, in: text).map { SyntaxSpan(range: $0.range, kind: kind) } }
    }

    private static func html(_ text: String) -> [SyntaxSpan] {
        let source = text as NSString
        var spans: [SyntaxSpan] = []
        // Compile once per document, then scan forward. Crucially, script bodies
        // are skipped before tokenization, including HTML-looking JS strings.
        let tokenExpression = try! NSRegularExpression(pattern: #"(?is)<!--.*?(?:-->|\z)|</?([A-Za-z][\w:-]*)(?:\"[^\"]*\"|'[^']*'|[^'\">]++)*+>"#)
        let attributeExpression = try! NSRegularExpression(pattern: #"([A-Za-z_:][\w:.-]*)(?:\s*=\s*(\"[^\"]*\"|'[^']*'|[^\s>]+))?"#)
        let entityExpression = try! NSRegularExpression(pattern: #"&(?:#\d+|#x[0-9A-Fa-f]+|[A-Za-z]+);"#)
        let scriptEnd = try! NSRegularExpression(pattern: #"(?i)</script\s*>"#)
        let styleEnd = try! NSRegularExpression(pattern: #"(?i)</style\s*>"#)
        var cursor = 0
        while cursor < source.length {
            let remainder = NSRange(location: cursor, length: source.length - cursor)
            let token = tokenExpression.firstMatch(in: text, range: remainder)
            let plainEnd = token?.range.location ?? source.length
            // Entities are meaningful in HTML text, never in skipped raw bodies.
            let plainRange = NSRange(location: cursor, length: plainEnd - cursor)
            entityExpression.enumerateMatches(in: text, range: plainRange) { match, _, _ in
                if let match { spans.append(SyntaxSpan(range: match.range, kind: .keyword)) }
            }
            guard let token else { break }
            cursor = NSMaxRange(token.range)
            let nameRange = token.range(at: 1)
            guard nameRange.location != NSNotFound else {
                spans.append(SyntaxSpan(range: token.range, kind: .comment)); continue
            }
            spans.append(SyntaxSpan(range: token.range, kind: .punctuation))
            spans.append(SyntaxSpan(range: nameRange, kind: .tag))
            let attributes = NSRange(location: NSMaxRange(nameRange), length: cursor - NSMaxRange(nameRange))
            attributeExpression.enumerateMatches(in: text, range: attributes) { attribute, _, _ in
                guard let attribute else { return }
                spans.append(SyntaxSpan(range: attribute.range(at: 1), kind: .attribute))
                let value = attribute.range(at: 2)
                if value.location != NSNotFound { spans.append(SyntaxSpan(range: value, kind: .string)) }
            }
            let name = source.substring(with: nameRange).lowercased()
            let isOpening = source.character(at: token.range.location + 1) != 47
            if isOpening && (name == "style" || name == "script") {
                let bodyRange = NSRange(location: cursor, length: source.length - cursor)
                let ending = name == "style" ? styleEnd : scriptEnd
                let close = ending.firstMatch(in: text, range: bodyRange)
                let end = close?.range.location ?? source.length
                if name == "style" {
                    spans += css(source.substring(with: NSRange(location: cursor, length: end - cursor)), offset: cursor)
                }
                // The next iteration handles the closing tag and following HTML.
                cursor = end
            }
        }
        return spans
    }

    private static func css(_ text: String, offset: Int) -> [SyntaxSpan] {
        var result: [SyntaxSpan] = []
        func append(_ range: NSRange, _ kind: SyntaxKind) {
            result.append(SyntaxSpan(range: NSRange(location: range.location + offset, length: range.length), kind: kind))
        }
        let rules: [(String, SyntaxKind)] = [
            (#"[{}:;,()\[\]>+~=]"#, .punctuation),
            (#"[.#][-\w]+"#, .selector),
            (#"(?<![\w#.-])-?(?:\d*\.\d+|\d+)(?:[A-Za-z]+|%)?"#, .number),
            (#"#[0-9A-Fa-f]{3,8}\b"#, .keyword),
            (#"\b[A-Za-z_-][\w-]*(?=\()|@[\w-]+|!important\b"#, .keyword)
        ]
        for (pattern, kind) in rules {
            for match in matches(pattern, in: text) { append(match.range, kind) }
        }
        for property in matches(#"(?s)(?:^|[;{])(?:\s|/\*.*?\*/)*([A-Za-z_-][\w-]*)\s*(?=:)"#, in: text) {
            append(property.range(at: 1), .tag)
        }
        // One lexical pass prevents comment markers in strings (and quotes in
        // comments) from changing the surrounding token's color.
        let lexical = #"(?s)/\*.*?(?:\*/|\z)|\"(?:\\.|[^\"\\])*(?:\"|\z)|'(?:\\.|[^'\\])*(?:'|\z)"#
        let source = text as NSString
        for match in matches(lexical, in: text) {
            append(match.range, source.substring(with: match.range).hasPrefix("/*") ? .comment : .string)
        }
        return result
    }
}
