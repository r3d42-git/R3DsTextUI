import Foundation
import XCTest
@testable import TextUICore

final class SessionNavigationTests: XCTestCase {
    func testNavigationCheckpointDoesNotRewriteTextAndRestoresSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(url: directory.appendingPathComponent("Session.json"))
        let token = UUID()
        let draft = Draft(file: TextFile(text: "😀 first\nsecond"))
        var session = Session(drafts: [draft], selected: draft.id, checkpointID: token)
        try store.save(session)
        let original = try Data(contentsOf: store.url)
        let modification = try FileManager.default.attributesOfItem(atPath: store.url.path)[.modificationDate] as? Date
        session.drafts[0].selection = 9; session.drafts[0].scrollY = 300
        try store.saveNavigation(SessionNavigation(session: session, checkpointID: token))
        XCTAssertEqual(try Data(contentsOf: store.url), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: store.url.path)[.modificationDate] as? Date, modification)
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.drafts[0].selection, 9)
        XCTAssertEqual(restored.drafts[0].scrollY, 300)
        XCTAssertEqual(restored.drafts[0].file.text, draft.file.text)
        XCTAssertLessThan(try Data(contentsOf: store.navigationURL).count, 500)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.navigationURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testStaleAndCorruptNavigationNeverResurrectDiscardedDrafts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(url: directory.appendingPathComponent("Session.json"))
        let old = Session(drafts: [Draft(file: TextFile(text: "discard me"))], selected: nil, checkpointID: UUID())
        try store.save(old)
        try store.saveNavigation(SessionNavigation(session: old, checkpointID: old.checkpointID!))
        let fresh = Session(drafts: [Draft(file: TextFile(text: "keep me"))], selected: nil, checkpointID: UUID())
        try store.save(fresh)
        XCTAssertEqual(try store.load()?.drafts.map(\.file.text), ["keep me"])
        try Data("invalid".utf8).write(to: store.navigationURL)
        XCTAssertEqual(try store.load()?.drafts.map(\.file.text), ["keep me"])
        // Legacy v1 sessions without a checkpoint ID remain readable.
        let legacy = "{\"version\":1,\"drafts\":[]}"
        try Data(legacy.utf8).write(to: store.url)
        XCTAssertEqual(try store.load()?.drafts.count, 0)
    }
}
