import Foundation

/// Only web destinations are handed to the default browser. Local files and
/// application URL schemes never leave the offline preview.
public enum PreviewLinks {
    public static func browserURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    public static func isDocumentAnchor(_ url: URL) -> Bool {
        // Foundation versions differ in URL.path for opaque URLs such as about:blank.
        // Match the exact offline document and fragment delimiter, without accepting queries.
        url.absoluteString.hasPrefix("about:blank#")
    }
}
