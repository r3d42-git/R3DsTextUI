import AppKit
import TextUICore

/// Physical source lines give the overview a stable shape independent of TextKit wrapping.
/// The immutable index is rebuilt only after source/syntax changes, never while scrolling.
struct MinimapDocument {
    struct Line { let start: Int; let length: Int }
    let source: NSString
    let spans: [SyntaxSpan]
    let lines: [Line]
    init(text: String, spans: [SyntaxSpan]) {
        source = text as NSString
        self.spans = spans
        var lines: [Line] = [], start = 0
        while start < source.length {
            var end = 0, contentsEnd = 0
            source.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
            lines.append(Line(start: start, length: max(0, contentsEnd - start)))
            start = end
        }
        if lines.isEmpty || (source.length > 0 && [10, 13, 0x2028, 0x2029].contains(source.character(at: source.length - 1))) {
            lines.append(Line(start: source.length, length: 0))
        }
        self.lines = lines
    }
    func row(at location: Int) -> Int {
        var low = 0, high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].start <= location { low = middle + 1 } else { high = middle }
        }
        return max(0, low - 1)
    }
    func location(atRow row: Int) -> Int { lines[min(lines.count - 1, max(0, row))].start }
}

/// Only actual rows in the visible overview window are sampled, never a squeezed file.
struct MinimapSnapshot {
    static let width = 96
    static let maximumHeight = 512
    let firstRow: Int
    let height: Int
    let pixels: [UInt8]
    init(document: MinimapDocument, firstRow: Int, rows: Int) {
        self.firstRow = min(document.lines.count - 1, max(0, firstRow))
        height = min(Self.maximumHeight, max(1, rows), document.lines.count - self.firstRow)
        var pixels = [UInt8](repeating: 0, count: height * Self.width)
        var samples: [(Int, Int)] = []
        samples.reserveCapacity(pixels.count)
        for y in 0..<height {
            let line = document.lines[self.firstRow + y]
            var x = 0
            for offset in 0..<min(line.length, Self.width) {
                let location = line.start + offset
                let character = document.source.character(at: location)
                if character == 9 { x = (x / 4 + 1) * 4 }
                else {
                    if x < Self.width && character != 32 {
                        let pixel = y * Self.width + x
                        pixels[pixel] = 1; samples.append((location, pixel))
                    }
                    x += 1
                }
                if x >= Self.width { break }
            }
        }
        for span in document.spans {
            guard let first = samples.first, let last = samples.last,
                  NSMaxRange(span.range) > first.0, span.range.location <= last.0 else { continue }
            var low = 0, high = samples.count
            while low < high {
                let middle = (low + high) / 2
                if samples[middle].0 < span.range.location { low = middle + 1 } else { high = middle }
            }
            while low < samples.count && samples[low].0 < NSMaxRange(span.range) {
                pixels[samples[low].1] = Self.code(span.kind); low += 1
            }
        }
        self.pixels = pixels
    }
    static func code(_ kind: SyntaxKind) -> UInt8 {
        switch kind {
        case .tag: return 2
        case .attribute, .keyword, .selector: return 3
        case .string, .heading: return 4
        case .strong: return 5
        case .number: return 6
        case .comment: return 7
        case .punctuation: return 1
        }
    }
}

final class EditorMinimap: NSView {
    static let rowHeight: CGFloat = 3
    override var isFlipped: Bool { true }
    private let queue = DispatchQueue(label: "TextUI.minimap", qos: .utility)
    private var generation = 0
    private var tileGeneration = 0
    private var work: DispatchWorkItem?
    private var tileWork: DispatchWorkItem?
    private var document: MinimapDocument?
    private var snapshot: MinimapSnapshot?
    private var image: NSImage?
    private var viewport = NSRange(location: 0, length: 0)
    private var firstRow = 0
    private var requestedTileRow = -1
    private var requestedTileRows = -1
    private var dragging = false
    private var dragOffset: CGFloat = 0
    private var navigationOnMouseUp = false
    private var lastNavigation = Date.distantPast
    var onNavigate: ((Int) -> Void)?
    private var visibleRows: Int { min(MinimapSnapshot.maximumHeight, max(1, Int(ceil(bounds.height / Self.rowHeight)))) }
    var contentRect: NSRect {
        NSRect(x: 4, y: 0, width: max(0, bounds.width - 8), height: min(bounds.height, CGFloat(max(0, (document?.lines.count ?? 0) - firstRow)) * Self.rowHeight))
    }
    var viewportRect: NSRect {
        guard let document else { return .zero }
        let top = CGFloat(document.row(at: viewport.location) - firstRow) * Self.rowHeight
        let bottom = CGFloat(document.row(at: NSMaxRange(viewport)) - firstRow + 1) * Self.rowHeight
        return NSRect(x: 1, y: top, width: max(0, bounds.width - 2), height: max(Self.rowHeight, bottom - top)).intersection(bounds)
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        clipsToBounds = true
        toolTip = "Dokumentübersicht · Klicken, sichtbaren Bereich ziehen oder hier scrollen"
        setAccessibilityLabel("Minimap – Dokumentübersicht")
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    func update(text: String, spans: [SyntaxSpan]) {
        generation += 1
        let generation = generation
        work?.cancel()
        let work = DispatchWorkItem { [weak self] in
            let document = MinimapDocument(text: text, spans: spans)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                self.document = document
                self.requestedTileRow = -1
                self.followViewport()
            }
        }
        self.work = work
        queue.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    func invalidate() {
        generation += 1; tileGeneration += 1
        work?.cancel(); tileWork?.cancel()
        document = nil; snapshot = nil; image = nil; requestedTileRow = -1
        needsDisplay = true
    }
    func updateViewport(_ range: NSRange) {
        viewport = range
        if !dragging { followViewport() }
        needsDisplay = true
    }
    func resizeOverview() { followViewport() }
    private func followViewport() {
        guard let document else { return }
        let row = document.row(at: viewport.location)
        let maximumStart = max(0, document.lines.count - visibleRows)
        // A moving overview keeps the viewport near the same proportional position
        // as in the document, while every rendered source line keeps its own spacing.
        if !dragging { firstRow = Int(CGFloat(row) / CGFloat(max(1, document.lines.count - 1)) * CGFloat(maximumStart)) }
        renderTile()
        needsDisplay = true
    }
    private func renderTile() {
        guard let document else { return }
        guard requestedTileRow != firstRow || requestedTileRows != visibleRows else { return }
        requestedTileRow = firstRow; requestedTileRows = visibleRows
        tileGeneration += 1
        let generation = generation, tileGeneration = tileGeneration, firstRow = firstRow, rows = visibleRows
        tileWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            let snapshot = MinimapSnapshot(document: document, firstRow: firstRow, rows: rows)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation, self.tileGeneration == tileGeneration else { return }
                self.snapshot = snapshot; self.image = nil; self.needsDisplay = true
            }
        }
        tileWork = work
        queue.async(execute: work)
    }
    func refreshColors() { image = nil; needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshColors() }
    private func makeImage(_ snapshot: MinimapSnapshot) -> NSImage? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: MinimapSnapshot.width, pixelsHigh: snapshot.height * 3,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bitmapFormat: .alphaNonpremultiplied, bytesPerRow: MinimapSnapshot.width * 4, bitsPerPixel: 32), let bytes = bitmap.bitmapData else { return nil }
        var palette: [[UInt8]] = [[0, 0, 0, 0]]
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for color in [EditorTheme.foreground, EditorTheme.cyan, EditorTheme.orange, EditorTheme.green, EditorTheme.red, EditorTheme.purple, EditorTheme.comment] {
                let rgb = color.usingColorSpace(.deviceRGB) ?? color
                palette.append([UInt8(rgb.redComponent * 255), UInt8(rgb.greenComponent * 255), UInt8(rgb.blueComponent * 255), 230])
            }
        }
        memset(bytes, 0, snapshot.height * 3 * MinimapSnapshot.width * 4)
        for y in 0..<snapshot.height {
            for x in 0..<MinimapSnapshot.width {
                let color = palette[Int(snapshot.pixels[y * MinimapSnapshot.width + x])]
                // One ink row and two empty rows keep blank lines and code blocks distinct.
                for ink in 0..<1 {
                    let base = ((y * 3 + ink) * MinimapSnapshot.width + x) * 4
                    for component in 0..<4 { bytes[base + component] = color[component] }
                }
            }
        }
        let image = NSImage(size: NSSize(width: MinimapSnapshot.width, height: snapshot.height * 3))
        image.addRepresentation(bitmap)
        return image
    }
    override func draw(_ dirtyRect: NSRect) {
        EditorTheme.chrome.setFill(); bounds.fill()
        if let snapshot {
            if image == nil { image = makeImage(snapshot) }
            NSGraphicsContext.current?.imageInterpolation = .none
            let rect = NSRect(x: 4, y: CGFloat(snapshot.firstRow - firstRow) * Self.rowHeight,
                width: max(0, bounds.width - 8), height: CGFloat(snapshot.height) * Self.rowHeight)
            image?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.9, respectFlipped: true, hints: nil)
        }
        EditorTheme.selection.withAlphaComponent(0.20).setFill(); viewportRect.fill()
        EditorTheme.currentNumber.withAlphaComponent(0.55).setStroke()
        NSBezierPath(rect: viewportRect.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let rect = viewportRect
        dragging = true
        navigationOnMouseUp = !rect.contains(point)
        if rect.contains(point) { dragOffset = point.y - rect.minY }
        else { dragOffset = min(rect.height / 2, 15); navigate(point.y, force: true) }
    }
    override func mouseDragged(with event: NSEvent) {
        navigationOnMouseUp = true
        navigate(convert(event.locationInWindow, from: nil).y, force: false)
    }
    override func mouseUp(with event: NSEvent) {
        if navigationOnMouseUp { navigate(convert(event.locationInWindow, from: nil).y, force: true) }
        dragging = false; navigationOnMouseUp = false; followViewport()
    }
    override func scrollWheel(with event: NSEvent) {
        guard let document else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / Self.rowHeight : event.scrollingDeltaY * 6
        let current = document.row(at: viewport.location)
        let step = Int(delta.rounded())
        if step != 0 { onNavigate?(document.location(atRow: current - step)) }
    }
    private func navigate(_ y: CGFloat, force: Bool) {
        guard let document else { return }
        guard force || Date().timeIntervalSince(lastNavigation) > 0.04 else { return }
        lastNavigation = Date()
        let row = firstRow + Int(max(0, min(bounds.height, y - dragOffset)) / Self.rowHeight)
        onNavigate?(document.location(atRow: row))
    }
}
