import Foundation

/// Only web destinations are handed to the default browser. Local files and
/// application URL schemes never leave the offline preview.
public enum PreviewLinks {
    /// A hierarchical internal address avoids OS-dependent parsing of opaque about: URLs.
    /// The reserved .invalid host is never fetched: loadHTMLString supplies content and CSP blocks network.
    public static let documentURL = URL(string: "https://textui-preview.invalid/")!

    public static func browserURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty, host != documentURL.host,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    public static func isDocumentAnchor(_ url: URL) -> Bool {
        url.scheme == documentURL.scheme && url.host == documentURL.host &&
            url.path == "/" && url.port == nil && url.user == nil && url.password == nil &&
            url.query == nil && url.fragment != nil
    }
}
