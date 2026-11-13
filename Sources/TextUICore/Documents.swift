import Foundation

public enum DocumentFormat: String, Codable, Sendable {
    case text = "Text", markdown = "Markdown", html = "HTML", dokuwiki = "DokuWiki", json = "JSON", xml = "XML", shell = "Shell", python = "Python"
    public var supportsPreview: Bool {
        switch self {
        case .markdown, .html, .dokuwiki, .json, .xml: return true
        case .text, .shell, .python: return false
        }
    }
    public init(url: URL?, text: String = "") {
        switch url?.pathExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "html", "htm": self = .html
        case "json": self = .json
        case "xml": self = .xml
        case "command": self = .shell
        case "py": self = .python
        case "wiki", "dokuwiki": self = .dokuwiki
        case "txt", "", nil: self = DokuWikiSyntax.isLikelyDocument(text) ? .dokuwiki : .text
        default: self = .text
        }
    }
}

public struct TextFile: Codable, Equatable, Sendable {
    public var text: String
    public var encoding: UInt
    public var bom: Bool
    public init(text: String = "", encoding: UInt = String.Encoding.utf8.rawValue, bom: Bool = false) {
        self.text = text; self.encoding = encoding; self.bom = bom
    }
    public static func decode(_ data: Data) throws -> TextFile {
        let bytes = Array(data.prefix(3))
        let encoding: String.Encoding
        let offset: Int
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { encoding = .utf8; offset = 3 }
        else if bytes.starts(with: [0xFF, 0xFE]) { encoding = .utf16LittleEndian; offset = 2 }
        else if bytes.starts(with: [0xFE, 0xFF]) { encoding = .utf16BigEndian; offset = 2 }
        else { encoding = .utf8; offset = 0 }
        guard let text = String(data: data.dropFirst(offset), encoding: encoding), !text.contains("\0") else {
            throw EditorError.unsupportedEncoding
        }
        return TextFile(text: text, encoding: encoding.rawValue, bom: offset > 0)
    }
    public func data() throws -> Data {
        guard let encoded = text.data(using: String.Encoding(rawValue: encoding), allowLossyConversion: false) else {
            throw EditorError.unsupportedEncoding
        }
        var result = Data()
        if bom {
            switch String.Encoding(rawValue: encoding) {
            case .utf8: result.append(contentsOf: [0xEF, 0xBB, 0xBF])
            case .utf16LittleEndian: result.append(contentsOf: [0xFF, 0xFE])
            case .utf16BigEndian: result.append(contentsOf: [0xFE, 0xFF])
            default: break
            }
        }
        result.append(encoded)
        return result
    }
    public var lineEnding: String {
        text.contains("\r\n") ? "CRLF" : (text.contains("\r") ? "CR" : "LF")
    }
    public var newline: String { lineEnding == "CRLF" ? "\r\n" : (lineEnding == "CR" ? "\r" : "\n") }
    public var encodingName: String { encoding == String.Encoding.utf8.rawValue ? "UTF-8" : "UTF-16" }
}

public enum EditorError: LocalizedError {
    case unsupportedEncoding, externalChange, invalidSession
    public var errorDescription: String? {
        switch self {
        case .unsupportedEncoding: return "Die Datei ist kein unterstützter Text. Der erste Entwurf unterstützt UTF-8 und UTF-16 mit BOM."
        case .externalChange: return "Die Datei wurde außerhalb von TextUI geändert oder entfernt. Speichere deinen Stand unter einem anderen Namen oder öffne die Datei erneut."
        case .invalidSession: return "Die gespeicherte Sitzung konnte nicht gelesen werden. Sie wurde nicht überschrieben."
        }
    }
}

public struct Draft: Codable, Identifiable, Sendable {
    public var id: UUID
    public var url: URL?
    public var file: TextFile
    public var baseline: Data?
    public var selection: Int
    public var scrollY: Double
    public init(id: UUID = UUID(), url: URL? = nil, file: TextFile = TextFile(), baseline: Data? = nil, selection: Int = 0, scrollY: Double = 0) {
        self.id = id; self.url = url; self.file = file; self.baseline = baseline; self.selection = selection; self.scrollY = scrollY
    }
    public var isDirty: Bool {
        guard let baseline else { return !file.text.isEmpty }
        return (try? file.data()) != baseline
    }
    public var title: String { url?.lastPathComponent ?? "Unbenannt" }
    public var format: DocumentFormat { DocumentFormat(url: url, text: file.text) }
    public static func open(_ url: URL) throws -> Draft {
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        let data = try Data(contentsOf: url)
        return Draft(url: url, file: try TextFile.decode(data), baseline: data)
    }
    public mutating func save(to destination: URL) throws {
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        if destination == url, (try? Data(contentsOf: destination)) != baseline { throw EditorError.externalChange }
        let data = try file.data()
        try data.write(to: destination, options: .atomic)
        url = destination; baseline = data
    }
}

public struct Session: Codable, Sendable {
    public var version = 1
    public var drafts: [Draft]
    public var selected: UUID?
    public var checkpointID: UUID?
    public init(drafts: [Draft], selected: UUID?, checkpointID: UUID? = nil) {
        self.drafts = drafts; self.selected = selected; self.checkpointID = checkpointID
    }
}

public struct SessionNavigation: Codable, Sendable {
    public struct Entry: Codable, Sendable {
        public let id: UUID
        public let selection: Int
        public let scrollY: Double
    }
    public let checkpointID: UUID
    public let selected: UUID?
    public let entries: [Entry]
    public init(session: Session, checkpointID: UUID) {
        self.checkpointID = checkpointID; selected = session.selected
        entries = session.drafts.map { Entry(id: $0.id, selection: $0.selection, scrollY: $0.scrollY) }
    }
}

public struct SessionStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Session? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var session = try JSONDecoder().decode(Session.self, from: Data(contentsOf: url))
        guard session.version == 1 else { throw EditorError.invalidSession }
        // A stale or unreadable navigation checkpoint never invalidates saved text.
        if let data = try? Data(contentsOf: navigationURL),
           let navigation = try? JSONDecoder().decode(SessionNavigation.self, from: data),
           navigation.checkpointID == session.checkpointID {
            for index in session.drafts.indices {
                if let entry = navigation.entries.first(where: { $0.id == session.drafts[index].id }) {
                    session.drafts[index].selection = min(max(0, entry.selection), (session.drafts[index].file.text as NSString).length)
                    session.drafts[index].scrollY = entry.scrollY.isFinite ? max(0, entry.scrollY) : 0
                }
            }
            if navigation.selected == nil || session.drafts.contains(where: { $0.id == navigation.selected }) {
                session.selected = navigation.selected
            }
        }
        return session
    }
    public func save(_ session: Session) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(session).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public var navigationURL: URL { url.deletingPathExtension().appendingPathExtension("navigation.json") }
    public func saveNavigation(_ navigation: SessionNavigation) throws {
        try JSONEncoder().encode(navigation).write(to: navigationURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: navigationURL.path)
    }
}
