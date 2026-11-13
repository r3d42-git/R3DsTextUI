import Foundation
import XCTest
@testable import TextUICore

final class BoundedSearchTests: XCTestCase {
    func testLiteralUnicodeRegexWholeWordsAndInvalidPatterns() throws {
        let text = "😀 cat CAT scatter a.b"
        XCTAssertEqual(try SearchOptions(wholeWord: true).boundedMatches(in: text, query: "cat"),
                       [NSRange(location: 3, length: 3), NSRange(location: 7, length: 3)])
        XCTAssertEqual(try SearchOptions(caseSensitive: true).boundedMatches(in: text, query: "cat").count, 2)
        XCTAssertEqual(try SearchOptions().boundedMatches(in: text, query: "a.b"), [NSRange(location: 19, length: 3)])
        XCTAssertEqual(try SearchOptions(regex: true).boundedMatches(in: "a12 b345", query: "\\d+"),
                       [NSRange(location: 1, length: 2), NSRange(location: 5, length: 3)])
        XCTAssertThrowsError(try SearchOptions(regex: true).boundedMatches(in: text, query: "["))
        XCTAssertEqual(try SearchOptions().boundedMatches(in: text, query: ""), [])
    }

    func testBacktrackingWithoutAnyMatchIsInterruptedByBudget() {
        let source = String(repeating: "a", count: 100) + "!"
        let start = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try SearchOptions(regex: true).boundedMatches(in: source, query: "(a+)+$", timeLimit: 0.03)) {
            XCTAssertEqual($0 as? SearchFailure, .timedOut)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 1)
    }

    func testCancellationInterruptsBacktrackingAndDiscardsPartialMatches() {
        let source = "x " + String(repeating: "a", count: 100) + "!"
        var callbacks = 0
        XCTAssertThrowsError(try SearchOptions(regex: true).boundedMatches(in: source, query: "x|(a+)+$", timeLimit: 1, cancelled: {
            callbacks += 1
            return callbacks > 3
        })) { XCTAssertEqual($0 as? SearchFailure, .cancelled) }
        XCTAssertGreaterThan(callbacks, 3)
    }
}
