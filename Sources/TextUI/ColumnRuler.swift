import AppKit

/// A viewport-sized visual column scale; drawing only queries visible text
/// layout. Tabs occupy their rendered width and wrapped fragments restart
/// at the same left edge. These are font cells, not UTF-16 character indices.
final class ColumnRuler: NSView {
    private weak var editor: NSTextView?
    private weak var scrollView: NSScrollView?
    override var isFlipped: Bool { true }

    init(textView: NSTextView, scrollView: NSScrollView) {
        editor = textView
        self.scrollView = scrollView
        super.init(frame: .zero)
        clipsToBounds = true
        toolTip = "Visuelle Textspalten: Tabulatoren belegen ihre sichtbare Breite; umgebrochene Zeilen beginnen wieder bei Spalte 1."
        setAccessibilityLabel("Spaltenleiste")
    }

    required init?(coder: NSCoder) { fatalError("Use init(textView:scrollView:)") }

    var characterAdvance: CGFloat {
        let font = editor?.font ?? EditorTheme.font(size: 14)
        return max(1, ("0" as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Convert through the native clip view so the scale follows the actual
    /// document origin, inset, padding and horizontal scroll position.
    func position(ofColumn column: Int) -> CGFloat {
        guard let editor else { return 0 }
        let origin = NSPoint(x: editor.textContainerOrigin.x + (editor.textContainer?.lineFragmentPadding ?? 0), y: 0)
        return convert(origin, from: editor).x + CGFloat(column - 1) * characterAdvance
    }

    var textViewport: NSRect {
        guard let clip = scrollView?.contentView else { return .zero }
        let viewport = convert(clip.bounds, from: clip)
        return NSRect(x: viewport.minX, y: 0, width: viewport.width, height: bounds.height).intersection(bounds)
    }

    /// AppKit supplies the insertion rectangle, including tab stops, composed
    /// characters and soft-wrap affinity. Check the visible character range
    /// first so a cursor left elsewhere by minimap navigation cannot trigger
    /// layout of an offscreen paragraph just to draw the scale.
    var caretPosition: CGFloat? {
        guard !isHidden, let editor, let window = editor.window,
              editor.selectedRanges.count == 1, editor.selectedRange().length == 0,
              let layout = editor.layoutManager, let container = editor.textContainer else { return nil }
        let location = editor.selectedRange().location
        let visible = editor.visibleRect
        let layoutRect = visible.offsetBy(dx: -editor.textContainerOrigin.x, dy: -editor.textContainerOrigin.y)
        let glyphs = layout.glyphRange(forBoundingRect: layoutRect, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        guard location >= characters.location, location <= NSMaxRange(characters) else { return nil }
        let screenRect = editor.firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
        guard screenRect.height > 0 else { return nil }
        let caretRect = editor.convert(window.convertFromScreen(screenRect), from: nil)
        guard caretRect.insetBy(dx: -0.5, dy: 0).intersects(visible) else { return nil }
        let x = convert(caretRect.origin, from: editor).x
        let viewport = textViewport
        return x >= viewport.minX && x <= viewport.maxX ? x : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.background.setFill()
        dirtyRect.intersection(bounds).fill()
        EditorTheme.gutter.withAlphaComponent(0.3).setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()

        let viewport = textViewport
        guard viewport.width > 0, viewport.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: viewport.intersection(dirtyRect)).addClip()
        let advance = characterAdvance
        let firstX = position(ofColumn: 1)
        let first = max(1, Int(floor((viewport.minX - firstX) / advance)) + 1)
        let last = max(first, Int(ceil((viewport.maxX - firstX) / advance)) + 1)
        let font = EditorTheme.font(size: 10)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: EditorTheme.currentNumber]
        // Retain useful spacing for unusually large column numbers. Only the
        // visible viewport is enumerated, even for very long unwrapped lines.
        var majorInterval = 10
        let labelWidth = (String(last) as NSString).size(withAttributes: attributes).width + 8
        while CGFloat(majorInterval) * advance < labelWidth { majorInterval *= 10 }
        let minorInterval = advance >= 6 ? 1 : 5
        let ticks = NSBezierPath()
        ticks.lineWidth = 1
        for column in first...last {
            let major = column == 1 || column % majorInterval == 0
            guard major || column % minorInterval == 0 else { continue }
            let x = firstX + CGFloat(column - 1) * advance
            ticks.move(to: NSPoint(x: x, y: bounds.maxY - (major ? 8 : 4)))
            ticks.line(to: NSPoint(x: x, y: bounds.maxY - 1))
            if major {
                let label = String(column) as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: x - size.width / 2, y: 2), withAttributes: attributes)
            }
        }
        EditorTheme.gutter.setStroke()
        ticks.stroke()
        if let x = caretPosition {
            let marker = NSBezierPath()
            marker.move(to: NSPoint(x: x - 4, y: bounds.maxY - 8))
            marker.line(to: NSPoint(x: x + 4, y: bounds.maxY - 8))
            marker.line(to: NSPoint(x: x, y: bounds.maxY - 2))
            marker.close()
            EditorTheme.cyan.setFill()
            marker.fill()
        }
    }
}
