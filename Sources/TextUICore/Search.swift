import Foundation

public struct SearchOptions: Sendable {
    public var caseSensitive = false
    public var wholeWord = false
    public var regex = false
    public init(caseSensitive: Bool = false, wholeWord: Bool = false, regex: Bool = false) {
        self.caseSensitive = caseSensitive; self.wholeWord = wholeWord; self.regex = regex
    }
    public func expression(_ query: String) throws -> NSRegularExpression {
        var pattern = regex ? query : NSRegularExpression.escapedPattern(for: query)
        if wholeWord { pattern = "(?<![\\p{L}\\p{N}_])(?:" + pattern + ")(?![\\p{L}\\p{N}_])" }
        return try NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
    }
    public func matches(in text: String, query: String) throws -> [NSRange] {
        try boundedMatches(in: text, query: query)
    }
}

public struct OutlineEntry {
    public let title: String
    public let location: Int
}

public enum TextNavigation {
    public static func lineStarts(_ text: String) -> [Int] {
        let ns = text as NSString
        var starts = [0], index = 0
        while index < ns.length {
            let range = ns.lineRange(for: NSRange(location: index, length: 0))
            index = NSMaxRange(range)
            if index <= ns.length, index > 0 {
                let last = ns.character(at: index - 1)
                if index < ns.length || last == 10 || last == 13 || last == 0x2028 || last == 0x2029 { starts.append(index) }
            }
        }
        return starts
    }
    public static func position(_ text: String, at location: Int) -> (line: Int, column: Int) {
        position(text, at: location, lineStarts: lineStarts(text))
    }

    /// Reuse an index built for this text; caret movement only searches the
    /// index and counts graphemes within the current physical line.
    public static func position(_ text: String, at location: Int, lineStarts starts: [Int]) -> (line: Int, column: Int) {
        let ns = text as NSString
        let location = min(max(0, location), ns.length)
        var low = 0, high = starts.count
        while low < high {
            let middle = low + (high - low) / 2
            if starts[middle] <= location { low = middle + 1 } else { high = middle }
        }
        let line = max(0, low - 1)
        let prefix = ns.substring(with: NSRange(location: starts[line], length: location - starts[line]))
        return (line + 1, prefix.count + 1)
    }
    public static func outline(_ text: String, format: DocumentFormat) -> [OutlineEntry] {
        let pattern: String
        switch format {
        case .markdown: pattern = "(?m)^#{1,6}\\s+(.+)$"
        case .html: pattern = "(?is)<h[1-6]\\b[^>]*>(.*?)</h[1-6]\\s*>"
        case .text, .json, .xml, .shell, .python: return []
        case .dokuwiki: return DokuWikiSyntax.outline(text)
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            OutlineEntry(title: ns.substring(with: $0.range(at: 1)).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression), location: $0.range.location)
        }
    }
}
