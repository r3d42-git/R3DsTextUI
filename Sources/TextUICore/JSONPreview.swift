import Foundation

/// Formats lexical JSON values without decoding/re-encoding numbers or object keys.
/// This preserves precision, duplicate keys, key order, and string escapes.
public enum JSONPreview {
    public static func formatted(_ source: String) throws -> String {
        var parser = Parser(bytes: Array(source.utf8))
        try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.bytes.count else { throw parser.failure("Unerwarteter Inhalt nach dem JSON-Wert.") }
        return parser.output
    }

    public static func html(from source: String) -> String {
        do {
            return MarkdownPreview.document(body: "<p>JSON · Gültig</p><pre><code>\(escape(try formatted(source)))</code></pre>")
        } catch {
            return MarkdownPreview.document(body: "<h2>JSON-Vorschau nicht verfügbar</h2><p>\(escape(error.localizedDescription))</p><p>Der Quelltext lässt sich weiterhin bearbeiten und speichern.</p>")
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private struct JSONPreviewError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct Parser {
    let bytes: [UInt8]
    var index = 0
    var output = ""
    var current: UInt8? { index < bytes.count ? bytes[index] : nil }
    mutating func whitespace() {
        while let byte = current, [9, 10, 13, 32].contains(byte) { index += 1 }
    }
    func failure(_ message: String) -> JSONPreviewError {
        let prefix = String(decoding: bytes[..<index], as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        return JSONPreviewError(message: "Zeile \(lines.count), Spalte \((lines.last?.count ?? 0) + 1): \(message)")
    }
    mutating func newline(_ depth: Int) { output += "\n" + String(repeating: "  ", count: depth) }
    mutating func value(depth: Int) throws {
        whitespace()
        guard depth < 256 else { throw failure("Die Verschachtelung ist für die Vorschau zu tief (maximal 256 Ebenen).") }
        guard let byte = current else { throw failure("JSON-Wert erwartet.") }
        switch byte {
        case 123, 91: try container(depth: depth)
        case 34: try string()
        case 116: try literal("true")
        case 102: try literal("false")
        case 110: try literal("null")
        case 45, 48...57: try number()
        default: throw failure("JSON-Wert erwartet.")
        }
    }
    mutating func container(depth: Int) throws {
        let object = current == 123
        let closing: UInt8 = object ? 125 : 93
        output += object ? "{" : "["; index += 1
        whitespace()
        if current == closing { output += object ? "}" : "]"; index += 1; return }
        while true {
            newline(depth + 1)
            if object {
                whitespace()
                guard current == 34 else { throw failure("Objektschlüssel in doppelten Anführungszeichen erwartet.") }
                try string(); whitespace()
                guard current == 58 else { throw failure("Doppelpunkt erwartet.") }
                index += 1; output += ": "
            }
            try value(depth: depth + 1); whitespace()
            if current == closing { newline(depth); output += object ? "}" : "]"; index += 1; return }
            guard current == 44 else { throw failure(object ? "Komma oder schließende geschweifte Klammer erwartet." : "Komma oder schließende eckige Klammer erwartet.") }
            index += 1; output += ","
        }
    }
    mutating func string() throws {
        let start = index
        index += 1
        while let byte = current {
            if byte == 34 {
                index += 1
                output += String(decoding: bytes[start..<index], as: UTF8.self)
                return
            }
            guard byte >= 32 else { throw failure("Steuerzeichen in Zeichenketten müssen maskiert werden.") }
            if byte == 92 {
                index += 1
                guard let escaped = current else { throw failure("Unvollständige Escape-Sequenz.") }
                if escaped == 117 {
                    for _ in 0..<4 {
                        index += 1
                        guard let hex = current, (48...57).contains(hex) || (65...70).contains(hex) || (97...102).contains(hex) else {
                            throw failure("Unicode-Escape benötigt vier Hexadezimalziffern.")
                        }
                    }
                } else if ![34, 92, 47, 98, 102, 110, 114, 116].contains(escaped) {
                    throw failure("Ungültige Escape-Sequenz.")
                }
            }
            index += 1
        }
        throw failure("Schließendes Anführungszeichen fehlt.")
    }
    mutating func literal(_ token: String) throws {
        guard bytes[index...].starts(with: token.utf8) else { throw failure("JSON-Wert erwartet.") }
        index += token.utf8.count; output += token
    }
    mutating func number() throws {
        let start = index
        if current == 45 { index += 1 }
        if current == 48 { index += 1 }
        else { try digits() }
        if current == 46 { index += 1; try digits() }
        if current == 101 || current == 69 {
            index += 1
            if current == 43 || current == 45 { index += 1 }
            try digits()
        }
        output += String(decoding: bytes[start..<index], as: UTF8.self)
    }
    mutating func digits() throws {
        let start = index
        while let byte = current, (48...57).contains(byte) { index += 1 }
        guard index > start else { throw failure("Ziffer erwartet.") }
    }
}
