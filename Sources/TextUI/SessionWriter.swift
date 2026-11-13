import Foundation
import TextUICore

/// Serializes immutable snapshots off the UI thread. Explicit close/save barriers
/// wait for older writes before committing so they cannot resurrect discarded tabs.
final class SessionWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "TextUI.session", qos: .utility)

    func save(_ session: Session, to store: SessionStore, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result = Result { try store.save(session) }
            DispatchQueue.main.async { completion(result) }
        }
    }
    func saveNavigation(_ navigation: SessionNavigation, to store: SessionStore, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result = Result { try store.saveNavigation(navigation) }
            DispatchQueue.main.async { completion(result) }
        }
    }
    func saveAndWait(_ session: Session, to store: SessionStore) throws {
        try queue.sync { try store.save(session) }
    }
    func flush() { queue.sync {} }
}
