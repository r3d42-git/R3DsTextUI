import AppKit

/// A small, appearance-aware card behind the existing native tab controls.
final class DocumentTabView: NSStackView {
    var isSelected = false

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1.5, dy: 2.5)
        guard rect.width > 0, rect.height > 2 else { return }
        let card = NSRect(x: rect.minX, y: rect.minY, width: rect.width,
                          height: rect.height - (isSelected ? 0 : 2))
        let path = NSBezierPath()
        let radius: CGFloat = 10
        let cornerInset = radius * (1 - 0.5522847498)
        path.move(to: NSPoint(x: card.minX, y: card.minY))
        path.line(to: NSPoint(x: card.minX, y: card.maxY - radius))
        path.curve(to: NSPoint(x: card.minX + radius, y: card.maxY),
                   controlPoint1: NSPoint(x: card.minX, y: card.maxY - cornerInset),
                   controlPoint2: NSPoint(x: card.minX + cornerInset, y: card.maxY))
        path.line(to: NSPoint(x: card.maxX - radius, y: card.maxY))
        path.curve(to: NSPoint(x: card.maxX, y: card.maxY - radius),
                   controlPoint1: NSPoint(x: card.maxX - cornerInset, y: card.maxY),
                   controlPoint2: NSPoint(x: card.maxX, y: card.maxY - cornerInset))
        path.line(to: NSPoint(x: card.maxX, y: card.minY))
        path.close()

        let top = isSelected ? EditorTheme.tabSelectedTop : EditorTheme.tabTop
        let bottom = isSelected ? EditorTheme.tabSelectedBottom : EditorTheme.tabBottom
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(isSelected ? 0.24 : 0.12)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        bottom.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: bottom, ending: top)?.draw(in: path, angle: 90)
        (isSelected ? EditorTheme.tabSelectedBorder : EditorTheme.tabBorder).setStroke()
        path.lineWidth = 1
        path.stroke()
        super.draw(dirtyRect)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
