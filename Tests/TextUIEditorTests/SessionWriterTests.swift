import Foundation
import XCTest
import TextUICore
@testable import TextUI

final class SessionWriterTests: XCTestCase {
    @MainActor
    func testLargeSnapshotRunsOffMainAndExplicitSaveWinsOverQueuedWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(url: directory.appendingPathComponent("Session.json"))
        let writer = SessionWriter()
        let source = String(repeating: "abcdefghi\n", count: 500_000)
        let baseline = Data(source.utf8)
        let draft = Draft(file: TextFile(text: source), baseline: baseline)
        let old = Session(drafts: Array(repeating: draft, count: 5), selected: draft.id, checkpointID: UUID())
        let saved = expectation(description: "background snapshot saved")
        writer.save(old, to: store) { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            saved.fulfill()
        }
        let responsive = expectation(description: "main queue remains available")
        DispatchQueue.main.async { responsive.fulfill() }
        await fulfillment(of: [responsive], timeout: 0.1)
        let final = Session(drafts: [Draft(file: TextFile(text: "latest text"))], selected: nil, checkpointID: UUID())
        try writer.saveAndWait(final, to: store)
        await fulfillment(of: [saved], timeout: 3)
        XCTAssertEqual(try store.load()?.drafts.map(\.file.text), ["latest text"])
        XCTAssertEqual(try store.load()?.checkpointID, final.checkpointID)
    }

    @MainActor
    func testWriteErrorIsReportedAndNextSaveCanRecover() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("file")
        try Data("not a directory".utf8).write(to: blocker)
        let writer = SessionWriter()
        let failed = expectation(description: "background error delivered")
        let session = Session(drafts: [Draft(file: TextFile(text: "preserve"))], selected: nil, checkpointID: UUID())
        writer.save(session, to: SessionStore(url: blocker.appendingPathComponent("Session.json"))) { result in
            guard case .failure = result else { XCTFail("Expected write error"); failed.fulfill(); return }
            failed.fulfill()
        }
        await fulfillment(of: [failed], timeout: 3)
        let store = SessionStore(url: directory.appendingPathComponent("Session.json"))
        try writer.saveAndWait(session, to: store)
        XCTAssertEqual(try store.load()?.drafts.first?.file.text, "preserve")
    }
}
