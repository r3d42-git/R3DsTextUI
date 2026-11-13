import Foundation

/// Display-only, forward-scanning tokens. This is deliberately not a shell or
/// Python parser: substitutions and f-strings are opaque, and no code is run.
/// Offsets use UTF-16, matching NSTextView and the other syntax highlighters.
enum ScriptSyntax {
    private static let shellKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
        "case", "esac", "in", "select", "function", "time", "coproc", "repeat",
        "export", "local", "readonly", "declare", "typeset", "return", "break", "continue"
    ]
    private static let pythonKeywords: Set<String> = [
        "False", "None", "True", "and", "as", "assert", "async", "await", "break",
        "class", "continue", "def", "del", "elif", "else", "except", "finally",
        "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal",
        "not", "or", "pass", "raise", "return", "try", "while", "with", "yield",
        "match", "case", "type"
    ]

    private static func digit(_ c: UInt16) -> Bool { (48...57).contains(c) }
    private static func letter(_ c: UInt16) -> Bool {
        (65...90).contains(c) || (97...122).contains(c) || c == 95 || c >= 128
    }
    private static func identifier(_ c: UInt16) -> Bool { letter(c) || digit(c) }
    private static func space(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
    private static func shellBoundary(_ c: UInt16) -> Bool {
        space(c) || [59, 38, 124, 40, 41, 60, 62].contains(c)
    }
    private static func token(_ units: [UInt16], _ start: Int, _ end: Int) -> String {
        String(decoding: units[start..<end], as: UTF16.self)
    }

    /// Consumes a quoted region, including an unfinished final region.
    private static func quoted(_ u: [UInt16], at start: Int, triple: Bool = false,
                               escapes: Bool = true, stopAtNewline: Bool = false) -> Int {
        let quote = u[start], width = triple ? 3 : 1
        var i = start + width
        while i < u.count {
            if escapes && u[i] == 92 { i = min(i + 2, u.count); continue }
            if stopAtNewline && (u[i] == 10 || u[i] == 13) { return i }
            if u[i] == quote {
                if !triple { return i + 1 }
                if i + 2 < u.count && u[i + 1] == quote && u[i + 2] == quote { return i + 3 }
            }
            i += 1
        }
        return i
    }

    private static func substitution(_ u: [UInt16], at start: Int) -> Int {
        var i = start + 1
        guard i < u.count else { return i }
        if u[i] == 123 || u[i] == 40 {
            let open = u[i], close: UInt16 = open == 123 ? 125 : 41
            var depth = 1
            i += 1
            while i < u.count {
                if u[i] == 92 { i = min(i + 2, u.count); continue }
                if u[i] == 34 || u[i] == 39 || u[i] == 96 {
                    i = quoted(u, at: i, escapes: u[i] != 39); continue
                }
                if u[i] == open { depth += 1 }
                if u[i] == close { depth -= 1; if depth == 0 { return i + 1 } }
                i += 1
            }
            return i
        }
        if digit(u[i]) || [63, 35, 36, 33, 45, 42, 64].contains(u[i]) { return i + 1 }
        while i < u.count && identifier(u[i]) { i += 1 }
        return i
    }

    static func shell(_ text: String) -> [SyntaxSpan] {
        let u = Array(text.utf16)
        var spans: [SyntaxSpan] = [], i = 0
        var atWordStart = true
        func append(_ start: Int, _ end: Int, _ kind: SyntaxKind) {
            spans.append(SyntaxSpan(range: NSRange(location: start, length: end - start), kind: kind))
        }
        while i < u.count {
            let start = i, c = u[i]
            if shellBoundary(c) { i += 1; atWordStart = true; continue }
            if c == 92 { i = min(i + 2, u.count); atWordStart = false; continue }
            if c == 35 && atWordStart {
                while i < u.count && u[i] != 10 && u[i] != 13 { i += 1 }
                append(start, i, .comment); continue
            }
            if c == 34 || c == 39 || c == 96 {
                i = quoted(u, at: i, escapes: c != 39)
                append(start, i, .string); atWordStart = false; continue
            }
            if c == 36 {
                i = substitution(u, at: i)
                if i > start + 1 { append(start, i, .attribute) }
                atWordStart = false; continue
            }
            // Scan literal word fragments together so e.g. file42 and foo#bar
            // do not acquire number or comment colors in their middle.
            while i < u.count && !shellBoundary(u[i]) && ![92, 34, 39, 96, 36].contains(u[i]) { i += 1 }
            let word = token(u, start, i)
            if atWordStart && shellKeywords.contains(word) { append(start, i, .keyword) }
            else if atWordStart && word.utf16.allSatisfy({ digit($0) }) { append(start, i, .number) }
            atWordStart = false
        }
        return spans
    }

    /// Numeric token recovery accepts incomplete exponents and base prefixes,
    /// useful while typing, without attempting to diagnose valid Python syntax.
    private static func numberEnd(_ u: [UInt16], at start: Int) -> Int {
        var i = start
        if u[i] == 43 || u[i] == 45 { i += 1 }
        if i + 1 < u.count && u[i] == 48 && [120, 88, 111, 79, 98, 66].contains(u[i + 1]) {
            i += 2
            while i < u.count && (digit(u[i]) || (65...70).contains(u[i]) || (97...102).contains(u[i]) || u[i] == 95) { i += 1 }
            return i
        }
        while i < u.count && (digit(u[i]) || u[i] == 95) { i += 1 }
        if i < u.count && u[i] == 46 {
            i += 1
            while i < u.count && (digit(u[i]) || u[i] == 95) { i += 1 }
        }
        if i < u.count && (u[i] == 101 || u[i] == 69) {
            i += 1
            if i < u.count && (u[i] == 43 || u[i] == 45) { i += 1 }
            while i < u.count && (digit(u[i]) || u[i] == 95) { i += 1 }
        }
        if i < u.count && (u[i] == 106 || u[i] == 74) { i += 1 }
        return i
    }

    static func python(_ text: String) -> [SyntaxSpan] {
        let u = Array(text.utf16)
        var spans: [SyntaxSpan] = [], i = 0, wantsName = false
        func append(_ start: Int, _ end: Int, _ kind: SyntaxKind) {
            spans.append(SyntaxSpan(range: NSRange(location: start, length: end - start), kind: kind))
        }
        while i < u.count {
            let start = i, c = u[i]
            if space(c) {
                if c == 10 || c == 13 { wantsName = false }
                i += 1; continue
            }
            if c == 35 {
                while i < u.count && u[i] != 10 && u[i] != 13 { i += 1 }
                append(start, i, .comment); continue
            }
            var quoteStart = i
            if letter(c) {
                while quoteStart < u.count && identifier(u[quoteStart]) { quoteStart += 1 }
                let prefix = token(u, i, quoteStart).lowercased()
                if !["r", "u", "b", "f", "br", "rb", "fr", "rf"].contains(prefix) { quoteStart = i }
            }
            if quoteStart < u.count && (u[quoteStart] == 34 || u[quoteStart] == 39) {
                let q = u[quoteStart]
                let triple = quoteStart + 2 < u.count && u[quoteStart + 1] == q && u[quoteStart + 2] == q
                // Raw strings also escape their quote delimiter with a backslash.
                i = quoted(u, at: quoteStart, triple: triple, stopAtNewline: !triple)
                append(start, i, .string); wantsName = false; continue
            }
            if letter(c) {
                i += 1
                while i < u.count && identifier(u[i]) { i += 1 }
                let word = token(u, start, i)
                if wantsName { append(start, i, .tag); wantsName = false }
                else if pythonKeywords.contains(word) {
                    append(start, i, .keyword)
                    wantsName = word == "def" || word == "class"
                }
                continue
            }
            let sign = (c == 43 || c == 45) && (start == 0 || space(u[start - 1]) || [40, 91, 123, 61, 58, 44].contains(u[start - 1]))
            let numberStart = sign ? i + 1 : i
            if numberStart < u.count && (digit(u[numberStart]) || (u[numberStart] == 46 && numberStart + 1 < u.count && digit(u[numberStart + 1]))) {
                i = numberEnd(u, at: start)
                append(start, i, .number); wantsName = false; continue
            }
            wantsName = false
            i += 1
        }
        return spans
    }
}
