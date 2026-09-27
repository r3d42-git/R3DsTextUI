import Foundation

/// Offline subset of DokuWiki syntax. Wiki plugins, media and server-side includes
/// are deliberately left as source text; no source HTML is executed.
public enum DokuWikiPreview {
    public static func html(from source: String) -> String {
        var renderer = WikiRenderer()
        return MarkdownPreview.document(body: renderer.render(source))
    }
}

private struct WikiRenderer {
    private var literals: [String: String] = [:]
    private let prefix = "WIKILITERAL" + UUID().uuidString.replacingOccurrences(of: "-", with: "")

    mutating func render(_ source: String) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let protected = protect(normalized)
        let lines = protected.components(separatedBy: "\n")
        var index = 0
        var result = blocks(lines, index: &index)
        for (token, html) in literals { result = result.replacingOccurrences(of: token, with: html) }
        return result
    }

    private mutating func protect(_ source: String) -> String {
        // Match complete literal regions before processing any formatting inside them.
        let pattern = #"(?is)<(code|file)(?:\s[^>]*)?>(.*?)(?:</\1\s*>|\z)|<nowiki>(.*?)(?:</nowiki\s*>|\z)|%%(.*?)(?:%%|\z)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let ns = source as NSString
        var result = "", cursor = 0
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let token = prefix + "X\(literals.count)X"
            if match.range(at: 2).location != NSNotFound {
                var value = ns.substring(with: match.range(at: 2))
                if value.hasPrefix("\n") { value.removeFirst() }
                let preceding = ns.substring(to: match.range.location).components(separatedBy: "\n").last ?? ""
                if !value.contains("\n"), !preceding.trimmingCharacters(in: .whitespaces).isEmpty {
                    literals[token] = "<code>\(escape(value))</code>"
                    result += token
                } else {
                    literals[token] = "<pre><code>\(escape(value))</code></pre>"
                    result += "\n\n" + token + "\n\n"
                }
            } else {
                let range = match.range(at: 3).location != NSNotFound ? match.range(at: 3) : match.range(at: 4)
                literals[token] = escape(ns.substring(with: range))
                result += token
            }
            cursor = NSMaxRange(match.range)
        }
        result += ns.substring(from: cursor)
        return result
    }

    private func blocks(_ lines: [String], index: inout Int) -> String {
        var result = "", paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { result += "<p>" + inline(paragraph.joined(separator: "\n")) + "</p>"; paragraph.removeAll() }
        }
        while index < lines.count {
            let line = lines[index], trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flush(); index += 1; continue }
            if let literal = literals[trimmed], literal.hasPrefix("<pre>") {
                flush(); result += trimmed; index += 1; continue
            }
            if let heading = heading(trimmed) {
                flush(); result += "<h\(heading.0)>\(inline(heading.1))</h\(heading.0)>"; index += 1; continue
            }
            if let item = listItem(line) {
                flush(); result += list(lines, index: &index, indent: item.indent); continue
            }
            if (trimmed.hasPrefix("|") || trimmed.hasPrefix("^")), (trimmed.hasSuffix("|") || trimmed.hasSuffix("^")) {
                flush(); result += "<div class=\"table-scroll\"><table>"
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard (row.hasPrefix("|") || row.hasPrefix("^")), (row.hasSuffix("|") || row.hasSuffix("^")) else { break }
                    result += tableRow(row); index += 1
                }
                result += "</table></div>"; continue
            }
            if trimmed.hasPrefix(">") {
                flush(); var quoted: [String] = []
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard row.hasPrefix(">") else { break }
                    quoted.append(String(row.dropFirst()).trimmingCharacters(in: .whitespaces)); index += 1
                }
                var quoteIndex = 0
                result += "<blockquote>" + blocks(quoted, index: &quoteIndex) + "</blockquote>"; continue
            }
            if trimmed.count >= 4 && trimmed.allSatisfy({ $0 == "-" }) { flush(); result += "<hr>"; index += 1; continue }
            paragraph.append(line); index += 1
        }
        flush(); return result
    }

    private func heading(_ line: String) -> (Int, String)? {
        let count = line.prefix(while: { $0 == "=" }).count
        guard (2...6).contains(count), line.count >= count * 2 else { return nil }
        let suffix = line.reversed().prefix(while: { $0 == "=" }).count
        guard suffix == count else { return nil }
        let title = String(line.dropFirst(count).dropLast(count)).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (7 - count, title)
    }

    private func listItem(_ line: String) -> (indent: Int, ordered: Bool, text: String)? {
        let spaces = line.prefix(while: { $0 == " " }).count
        guard spaces >= 2 else { return nil }
        let rest = line.dropFirst(spaces)
        guard let marker = rest.first, marker == "*" || marker == "-", rest.dropFirst().first?.isWhitespace == true else { return nil }
        return (spaces, marker == "-", String(rest.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    private func list(_ lines: [String], index: inout Int, indent: Int) -> String {
        guard index < lines.count, let first = listItem(lines[index]) else { return "" }
        let tag = first.ordered ? "ol" : "ul"
        var result = "<\(tag)>"
        while index < lines.count, let item = listItem(lines[index]), item.indent == indent, item.ordered == first.ordered {
            result += "<li>" + inline(item.text); index += 1
            while index < lines.count, let nested = listItem(lines[index]), nested.indent > indent {
                result += list(lines, index: &index, indent: nested.indent)
            }
            result += "</li>"
        }
        return result + "</\(tag)>"
    }

    private func tableRow(_ line: String) -> String {
        let chars = Array(line)
        var result = "<tr>", cell = "", delimiter = chars[0], index = 1, linkDepth = 0
        while index < chars.count {
            let c = chars[index]
            if c == "[", index + 1 < chars.count, chars[index + 1] == "[" { linkDepth += 1 }
            if c == "]", index + 1 < chars.count, chars[index + 1] == "]" { linkDepth = max(0, linkDepth - 1) }
            if (c == "|" || c == "^") && linkDepth == 0 {
                let tag = delimiter == "^" ? "th" : "td"
                let leading = cell.prefix(while: { $0 == " " }).count >= 2
                let trailing = cell.reversed().prefix(while: { $0 == " " }).count >= 2
                let align = leading ? (trailing ? " align=\"center\"" : " align=\"right\"") : ""
                result += "<\(tag)\(align)>" + inline(cell.trimmingCharacters(in: .whitespaces)) + "</\(tag)>"
                delimiter = c; cell = ""
            } else { cell.append(c) }
            index += 1
        }
        return result + "</tr>"
    }

    private func inline(_ source: String, depth: Int = 0) -> String {
        guard depth < 16 else { return escape(source) }
        var result = "", cursor = source.startIndex
        let formats = [("**", "strong"), ("//", "em"), ("__", "u"), ("''", "code"), ("<sub>", "sub"), ("<sup>", "sup"), ("<del>", "del")]
        while cursor < source.endIndex {
            let tail = source[cursor...]
            if tail.hasPrefix("[["), let end = tail.dropFirst(2).range(of: "]]") {
                let content = String(source[source.index(cursor, offsetBy: 2)..<end.lowerBound])
                let pieces = content.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                let target = String(pieces.first ?? "").trimmingCharacters(in: .whitespaces)
                let label = pieces.count > 1 ? String(pieces[1]) : target
                if safeLink(target) { result += "<a href=\"\(escape(target))\">\(inline(label, depth: depth + 1))</a>" }
                else { result += "<span>\(inline(label, depth: depth + 1))</span>" }
                cursor = end.upperBound; continue
            }
            if tail.hasPrefix("\\\\") {
                let after = source.index(cursor, offsetBy: 2)
                if after == source.endIndex || source[after].isWhitespace { result += "<br>"; cursor = after; continue }
            }
            var consumed = false
            for (marker, tag) in formats where tail.hasPrefix(marker) {
                // A URL's scheme separator is literal, not an emphasis delimiter.
                if marker == "//", cursor > source.startIndex, source[source.index(before: cursor)] == ":" { continue }
                let close = marker.hasPrefix("<") ? "</\(tag)>" : marker
                let start = source.index(cursor, offsetBy: marker.count)
                guard let end = source[start...].range(of: close), end.lowerBound > start else { continue }
                let content = String(source[start..<end.lowerBound])
                result += "<\(tag)>" + (tag == "code" ? escape(content) : inline(content, depth: depth + 1)) + "</\(tag)>"
                cursor = end.upperBound; consumed = true; break
            }
            if consumed { continue }
            result += escape(String(source[cursor])); cursor = source.index(after: cursor)
        }
        return result
    }

    private func safeLink(_ target: String) -> Bool {
        // Internal wiki pages have no local resolution; show their label without a live link.
        guard let url = URL(string: target), let scheme = url.scheme?.lowercased() else { return target.hasPrefix("#") }
        return ["https", "http", "mailto"].contains(scheme)
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
