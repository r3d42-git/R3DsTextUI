import Foundation

public enum SearchFailure: Error, Equatable, Sendable {
    case cancelled, timedOut
}

/// ICU progress callbacks also run during backtracking, before a match is found.
/// Discard partial results when the budget expires rather than showing a false count.
extension SearchOptions {
    public func boundedMatches(in text: String, query: String, timeLimit: TimeInterval = 0.2,
                               cancelled: @escaping () -> Bool = { false }) throws -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeLimit)
        let expression = try expression(query)
        var ranges: [NSRange] = []
        var failure: SearchFailure?
        expression.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(text.startIndex..., in: text)) { match, _, stop in
            if cancelled() { failure = .cancelled; stop.pointee = true }
            else if ProcessInfo.processInfo.systemUptime >= deadline { failure = .timedOut; stop.pointee = true }
            else if let match { ranges.append(match.range) }
        }
        if cancelled() { throw SearchFailure.cancelled }
        if let failure { throw failure }
        return ranges
    }
}
