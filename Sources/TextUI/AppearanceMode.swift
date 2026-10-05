import AppKit

enum AppearanceMode: String, CaseIterable {
    case light, dark, system

    init(savedValue: String?) { self = savedValue.flatMap(Self.init(rawValue:)) ?? .system }

    var title: String {
        switch self {
        case .light: return "Hell"
        case .dark: return "Dunkel"
        case .system: return "System"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }
}

/// Draw dynamic colors in the view's appearance instead of caching a layer CGColor.
final class ChromeStackView: NSStackView {
    var onAppearanceChange: (() -> Void)?
    private var appearanceRefreshPending = false

    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.windowChrome.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        // AppKit is still walking the window's descendants here. Update chrome
        // only after that traversal, coalescing repeated invalidations.
        guard !appearanceRefreshPending else { return }
        appearanceRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.appearanceRefreshPending = false
            self.onAppearanceChange?()
        }
    }
}
