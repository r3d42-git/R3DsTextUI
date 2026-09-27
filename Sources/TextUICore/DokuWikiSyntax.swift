import Foundation

/// The lightweight wiki recognition and editor tokens use UTF-16 coordinates,
/// matching NSTextView. Literal examples never contribute to the outline.
public enum DokuWikiSyntax {
    private static let headings = try! NSRegularExpression(pattern: #"(?m)^[\t ]*(={2,6})(?!=)[\t ]*([^=\r\n](?:[^\r\n]*?[^=\r\n])?)[\t ]*(?<!=)\1[\t ]*\r?$"#)
    private static let literals = try! NSRegularExpression(pattern: #"(?is)<(code|file|nowiki)\b[^>]*>.*?(?:</\1\s*>|\z)|%%.*?(?:%%|\z)"#)

    private static let links = try! NSRegularExpression(pattern: #"\[\[[^\]\r\n]+\]\]"#)
    private static let breaks = try! NSRegularExpression(pattern: #"\\\\(?=\s|$)"#)
    private static let tables = try! NSRegularExpression(pattern: #"(?m)^[\t ]*\^[^\r\n]*\^[\t ]*\r?$"#)

    /// Limit content sniffing so opening large plain files stays inexpensive.
    /// Require independent wiki signals rather than guessing from a Windows
    /// path, one HTML code example, or a decorative line of equals signs.
    public static func isLikelyDocument(_ text: String) -> Bool {
        let sample = String(text.prefix(32_768))
        let source = sample as NSString
        let full = NSRange(location: 0, length: source.length)
        let literalMatches = literals.matches(in: sample, range: full)
        let excluded = literalMatches.map(\.range)
        let headingCount = headings.matches(in: sample, range: full).filter { !overlaps($0.range, excluded) }.count
        let hasBlock = literalMatches.contains {
            let prefix = source.substring(with: NSRange(location: $0.range.location, length: min(5, $0.range.length))).lowercased()
            return prefix == "<code" || prefix == "<file"
        }
        func has(_ expression: NSRegularExpression) -> Bool {
            expression.matches(in: sample, range: full).contains { !overlaps($0.range, excluded) }
        }
        let hasLink = has(links)
        let hasBreak = has(breaks)
        let hasTable = has(tables)
        let signals = [headingCount > 0, hasBlock, hasLink, hasBreak, hasTable].filter { $0 }.count
        return headingCount >= 2 || signals >= 2
    }

    public static func outline(_ text: String) -> [OutlineEntry] {
        let source = text as NSString
        let excluded = literals.matches(in: text, range: NSRange(location: 0, length: source.length)).map(\.range)
        return headings.matches(in: text, range: NSRange(location: 0, length: source.length)).filter { !overlaps($0.range, excluded) }.map {
            OutlineEntry(title: source.substring(with: $0.range(at: 2)).trimmingCharacters(in: .whitespaces), location: $0.range.location)
        }
    }

    public static func spans(in text: String) -> [SyntaxSpan] {
        let full = NSRange(location: 0, length: (text as NSString).length)
        let excluded = literals.matches(in: text, range: full).map(\.range)
        var result = headings.matches(in: text, range: full).filter { !overlaps($0.range, excluded) }.map { SyntaxSpan(range: $0.range, kind: .heading) }
        let rules: [(String, SyntaxKind)] = [
            (#"\[\[[^\]\r\n]+\]\]"#, .selector),
            (#"\{\{[^}\r\n]+\}\}"#, .selector),
            (#"\*\*[^\r\n]+?\*\*|__[^\r\n]+?__"#, .strong),
            (#"''[^\r\n]+?''"#, .string),
            (#"\\\\(?=\s|$)"#, .keyword)
        ]
        for (pattern, kind) in rules {
            result += matches(pattern, text).filter { !overlaps($0.range, excluded) }.map { SyntaxSpan(range: $0.range, kind: kind) }
        }
        // Includes delimiters and unfinished blocks; their contents are literal.
        result += excluded.map { SyntaxSpan(range: $0, kind: .comment) }
        return result
    }

    private static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern))?.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) ?? []
    }

    private static func overlaps(_ range: NSRange, _ excluded: [NSRange]) -> Bool {
        // Literal matches are ordered, so stop before walking the rest of a file.
        for other in excluded {
            if other.location >= NSMaxRange(range) { break }
            if NSIntersectionRange(range, other).length > 0 { return true }
        }
        return false
    }
}
