import AppKit
import TextUICore

/// The editor owns native text layout; the controller owns the file and session.
final class EditorPane: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
    let scrollView: NSScrollView
    let view = NSView()
    let textView: NSTextView
    var onChange: (() -> Void)?
    var onSelection: (() -> Void)?
    private var format: DocumentFormat
    private var highlightWork: DispatchWorkItem?
    private var highlightGeneration = 0
    private(set) var gutter: LineNumberRuler!
    let columnRuler: ColumnRuler
    private var columnRulerHeight: NSLayoutConstraint!
    private var appliedFontSize: CGFloat?
    private var appliedWrap: Bool?
    private var requestedWrap = true
    private var updatingDocumentFrame = false
    let minimap = EditorMinimap(frame: .zero)
    private var minimapWidth: NSLayoutConstraint!
    private var minimapSpans: [SyntaxSpan] = []
    private var minimapVisible = true

    init(text: String, format: DocumentFormat, fontSize: CGFloat) {
        self.format = format
        scrollView = NSScrollView(frame: .zero)
        scrollView.clipsToBounds = true
        scrollView.contentView.clipsToBounds = true
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        layout.backgroundLayoutEnabled = false
        storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        let native = SourceTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        native.preferredNewline = TextFile(text: text).newline
        textView = native
        columnRuler = ColumnRuler(textView: native, scrollView: scrollView)
        super.init()
        native.isRichText = false
        native.importsGraphics = false
        native.allowsUndo = true
        native.isAutomaticQuoteSubstitutionEnabled = false
        native.isAutomaticDashSubstitutionEnabled = false
        native.isAutomaticTextReplacementEnabled = false
        native.isAutomaticSpellingCorrectionEnabled = false
        native.isContinuousSpellCheckingEnabled = false
        native.isGrammarCheckingEnabled = false
        native.isAutomaticLinkDetectionEnabled = false
        native.isAutomaticDataDetectionEnabled = false
        native.isAutomaticTextCompletionEnabled = false
        native.usesFindBar = false
        native.isIncrementalSearchingEnabled = false
        native.textContainerInset = NSSize(width: 12, height: 12)
        native.minSize = NSSize(width: 0, height: 0)
        native.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        native.isVerticallyResizable = true
        // TextKit owns the document frame. Implicit autoresizing constraints can
        // otherwise reset its height during scroll tiling and repeat layout.
        native.translatesAutoresizingMaskIntoConstraints = false

        native.backgroundColor = EditorTheme.background
        native.textColor = EditorTheme.foreground
        native.insertionPointColor = EditorTheme.currentNumber
        native.selectedTextAttributes = [.backgroundColor: EditorTheme.selection]
        native.string = text
        scrollView.documentView = native
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = EditorTheme.background
        gutter = LineNumberRuler(scrollView: scrollView, textView: native)
        view.clipsToBounds = true
        view.addSubview(gutter)
        view.addSubview(scrollView)
        view.addSubview(minimap)
        view.addSubview(columnRuler)
        columnRuler.translatesAutoresizingMaskIntoConstraints = false
        columnRulerHeight = columnRuler.heightAnchor.constraint(equalToConstant: 26)
        columnRulerHeight.isActive = true
        minimap.translatesAutoresizingMaskIntoConstraints = false
        minimapWidth = minimap.widthAnchor.constraint(equalToConstant: 136)
        minimapWidth.isActive = true
        minimap.onNavigate = { [weak self] location in
            guard let self else { return }
            let horizontalOrigin = self.scrollView.contentView.bounds.minX
            self.textView.scrollRangeToVisible(NSRange(location: location, length: 0))
            if let layout = self.textView.layoutManager {
                let length = (self.textView.string as NSString).length
                let rect: NSRect
                if location < length {
                    let glyph = layout.glyphIndexForCharacter(at: location)
                    rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
                } else { rect = layout.extraLineFragmentRect }
                if rect.height > 0 {
                    if let container = self.textView.textContainer { self.updateDocumentFrame(in: container) }
                    let clip = self.scrollView.contentView
                    var proposed = clip.bounds
                    proposed.origin = NSPoint(x: horizontalOrigin, y: location == 0 ? 0 : max(0, rect.minY + self.textView.textContainerOrigin.y))
                    clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
                }
            }
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
            self.updateMinimapViewport()
        }
        gutter.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gutter.topAnchor.constraint(equalTo: columnRuler.bottomAnchor),
            gutter.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: minimap.leadingAnchor),
            minimap.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            minimap.topAnchor.constraint(equalTo: columnRuler.bottomAnchor),
            minimap.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.topAnchor.constraint(equalTo: columnRuler.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            columnRuler.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            columnRuler.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            columnRuler.topAnchor.constraint(equalTo: view.topAnchor)
        ])
        native.delegate = self
        layout.delegate = self
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(viewportSizeChanged), name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(viewportScrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        minimap.update(text: text, spans: [])
        updateAppearance(format: format, fontSize: fontSize, wrap: true)
        scheduleHighlight()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
        guard let textContainer else { return }
        updateDocumentFrame(in: textContainer, layoutFinished: layoutFinishedFlag)
    }

    private func updateDocumentFrame(in textContainer: NSTextContainer, layoutFinished: Bool = false) {
        guard !updatingDocumentFrame, let layoutManager = textView.layoutManager else { return }
        // usedRect reads completed layout; it does not force the entire file to
        // be typeset. Extend the scrollable document as visible/target lines lay out.
        let used = layoutManager.usedRect(for: textContainer)
        let extra = layoutManager.extraLineFragmentRect
        let viewport = scrollView.contentSize
        let inset = textView.textContainerInset
        let width = requestedWrap ? max(viewport.width, textView.frame.width)
            : max(viewport.width, used.maxX + 2 * inset.width)
        let laidOutHeight = max(used.maxY, extra.maxY) + 2 * inset.height
        let height = max(viewport.height, layoutFinished ? laidOutHeight : max(textView.frame.height, laidOutHeight))
        let size = NSSize(width: width, height: height)
        guard abs(textView.frame.width - width) > 0.5 || abs(textView.frame.height - height) > 0.5 else { return }
        updatingDocumentFrame = true
        textView.setFrameSize(size)
        updatingDocumentFrame = false
    }

    /// Palette changes reuse the dynamic syntax attributes and minimap tokens.
    /// No storage editing, syntax scan, layout changes or selection notifications.
    func refreshColors() {
        textView.needsDisplay = true
        scrollView.needsDisplay = true
        gutter.needsDisplay = true
        columnRuler.needsDisplay = true
        minimap.refreshColors()
    }

    @objc private func viewportSizeChanged() { synchronizeWrapWidth(); updateMinimapColumns(); updateMinimapViewport(); columnRuler.needsDisplay = true }
    @objc private func viewportScrolled() { updateMinimapViewport(); columnRuler.needsDisplay = true }

    func setColumnRulerVisible(_ visible: Bool) {
        guard columnRuler.isHidden == visible else { return }
        columnRuler.isHidden = !visible
        columnRulerHeight.constant = visible ? 26 : 0
        finishRulerVisibilityChange()
    }

    func setLineNumbersVisible(_ visible: Bool) {
        guard gutter.isHidden == visible else { return }
        gutter.setVisible(visible)
        finishRulerVisibilityChange()
    }

    private func finishRulerVisibilityChange() {
        view.layoutSubtreeIfNeeded()
        synchronizeWrapWidth()
        updateMinimapColumns()
        updateMinimapViewport()
        gutter.needsDisplay = true
        columnRuler.needsDisplay = true
    }

    func setMinimapVisible(_ visible: Bool) {
        guard minimapVisible != visible else { return }
        minimapVisible = visible
        minimap.isHidden = !visible
        minimapWidth.constant = visible ? 136 : 0
        view.layoutSubtreeIfNeeded()
        synchronizeWrapWidth()
        updateMinimapColumns()
        if visible { minimap.update(text: textView.string, spans: minimapSpans); updateMinimapViewport() }
    }

    private func updateMinimapColumns() { minimap.resizeOverview() }

    private func updateMinimapViewport() {
        guard minimapVisible, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        // Query only the currently visible glyph region; never request the full container.
        let glyphs = layout.glyphRange(forBoundingRect: textView.visibleRect.offsetBy(dx: -textView.textContainerOrigin.x, dy: -textView.textContainerOrigin.y), in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        minimap.updateViewport(characters)
    }

    /// Autoresizing during attachment can preserve a provisional document width.
    /// The viewport, not that provisional frame, defines the wrapping boundary.
    private func synchronizeWrapWidth() {
        guard requestedWrap, let container = textView.textContainer else { return }
        let width = scrollView.contentSize.width
        guard width > 48 else { return }
        let containerWidth = max(1, width - 2 * textView.textContainerInset.width)
        if abs(textView.frame.width - width) > 0.5 {
            textView.setFrameSize(NSSize(width: width, height: max(textView.frame.height, scrollView.contentSize.height)))
        }
        if abs(container.containerSize.width - containerWidth) > 0.5 {
            container.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    func updateAppearance(format: DocumentFormat, fontSize: CGFloat, wrap: Bool) {
        requestedWrap = wrap
        let formatChanged = self.format != format
        self.format = format
        let effectiveWrap = wrap
        let fontChanged = appliedFontSize != fontSize
        let wrapChanged = appliedWrap != effectiveWrap
        guard fontChanged || wrapChanged || formatChanged else {
            synchronizeWrapWidth()
            return
        }
        if fontChanged {
            let font = EditorTheme.font(size: fontSize)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = max(2, fontSize * 0.18)
            paragraph.defaultTabInterval = font.maximumAdvancement.width * 4
            paragraph.tabStops = []
            textView.defaultParagraphStyle = paragraph
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: EditorTheme.foreground, .paragraphStyle: paragraph]
            if let storage = textView.textStorage {
                storage.beginEditing()
                storage.addAttributes(attributes, range: NSRange(location: 0, length: storage.length))
                storage.endEditing()
            }
            textView.typingAttributes = attributes
            appliedFontSize = fontSize
            gutter.updateWidth()
        }
        if wrapChanged {
            textView.isHorizontallyResizable = !effectiveWrap
            textView.autoresizingMask = effectiveWrap ? [.width] : []
            textView.textContainer?.widthTracksTextView = effectiveWrap
            let editorWidth = scrollView.contentSize.width > 48 ? scrollView.contentSize.width : max(600, textView.frame.width)
            textView.textContainer?.containerSize = NSSize(width: effectiveWrap ? max(1, editorWidth - 24) : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            if effectiveWrap {
                textView.setFrameSize(NSSize(width: editorWidth, height: max(textView.frame.height, scrollView.contentSize.height)))
            }
            scrollView.hasHorizontalScroller = !effectiveWrap
            appliedWrap = effectiveWrap
        }
        if formatChanged { scheduleHighlight() }
        synchronizeWrapWidth()
        gutter.needsDisplay = true
        columnRuler.needsDisplay = true
        updateMinimapColumns()
        updateMinimapViewport()
    }

    /// Call after the host has its final size, before restoring a saved viewport.
    func finishLayout() {
        scrollView.layoutSubtreeIfNeeded()
        synchronizeWrapWidth()
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(forBoundingRect: textView.visibleRect, in: container)
            updateDocumentFrame(in: container)
        }
        // Preserve horizontal scrolling; normalize only the vertical origin
        // left over from initial offscreen text layout.
        textView.setFrameOrigin(NSPoint(x: textView.frame.origin.x, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func textDidChange(_ notification: Notification) {
        gutter.rebuildLines()
        columnRuler.needsDisplay = true
        minimapSpans = []
        minimap.invalidate()
        if minimapVisible { minimap.update(text: textView.string, spans: []) }
        scheduleHighlight()
        onChange?()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        gutter.needsDisplay = true
        columnRuler.needsDisplay = true
        textView.needsDisplay = true
        onSelection?()
    }

    private func scheduleHighlight() {
        highlightWork?.cancel()
        highlightGeneration += 1
        let work = DispatchWorkItem { [weak self] in self?.highlight() }
        highlightWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    /// Temporary layout attributes keep syntax colors out of undo and file data.
    private func highlight() {
        guard let layout = textView.layoutManager else { return }
        let text = textView.string
        let range = NSRange(location: 0, length: (text as NSString).length)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        let generation = highlightGeneration
        let format = self.format
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let spans = SyntaxHighlighting.spans(in: text, format: format)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.highlightGeneration == generation,
                      let layout = self.textView.layoutManager else { return }
                self.minimapSpans = spans
                if self.minimapVisible { self.minimap.update(text: text, spans: spans); self.updateMinimapViewport() }
                for span in spans {
                    let color: NSColor
                    switch span.kind {
                    case .tag: color = EditorTheme.cyan
                    case .attribute, .keyword, .selector: color = EditorTheme.orange
                    case .string, .heading: color = EditorTheme.green
                    case .strong: color = EditorTheme.red
                    case .number: color = EditorTheme.purple
                    case .comment: color = EditorTheme.comment
                    case .punctuation: color = EditorTheme.foreground
                    }
                    layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: span.range)
                }
            }
        }
    }
}

private final class SourceTextView: NSTextView {
    var preferredNewline = "\n"

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layout = layoutManager, textContainer != nil else { return }
        let source = string as NSString
        let location = min(selectedRange().location, source.length)
        var highlightRect: NSRect
        if location < source.length {
            let glyph = layout.glyphIndexForCharacter(at: location)
            highlightRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
        } else {
            highlightRect = layout.extraLineFragmentRect
        }
        highlightRect.origin.y += textContainerOrigin.y
        highlightRect.origin.x = visibleRect.minX
        highlightRect.size.width = visibleRect.width
        if highlightRect.height < 1 { highlightRect.size.height = (font?.pointSize ?? 14) * 1.4 }
        EditorTheme.currentLine.setFill()
        highlightRect.intersection(rect).fill()
    }
    override func insertNewline(_ sender: Any?) {
        // Keep the document's existing convention, including Windows CRLF files.
        let source = string as NSString
        if source.length > 0 {
            let current = TextFile(text: string)
            if string.contains("\n") || string.contains("\r") { preferredNewline = current.newline }
        }
        let selection = selectedRange()
        let lineStart = source.lineRange(for: NSRange(location: min(selection.location, source.length), length: 0)).location
        let prefix = source.substring(with: NSRange(location: lineStart, length: max(0, selection.location - lineStart)))
        let indentation = String(prefix.prefix { $0 == " " || $0 == "\t" })
        insertText(preferredNewline + indentation, replacementRange: selection)
    }
}

final class LineNumberRuler: NSView {
    private var widthConstraint: NSLayoutConstraint!
    private var ruleThickness: CGFloat = 48 { didSet { widthConstraint?.constant = isHidden ? 0 : ruleThickness } }
    override var isFlipped: Bool { true }
    private weak var editor: NSTextView?
    private var starts = [0]

    init(scrollView: NSScrollView, textView: NSTextView) {
        editor = textView
        super.init(frame: .zero)
        widthConstraint = widthAnchor.constraint(equalToConstant: ruleThickness)
        widthConstraint.isActive = true
        clipsToBounds = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        rebuildLines()
    }
    required init(coder: NSCoder) { fatalError("Use init(scrollView:textView:)") }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func scrolled() { needsDisplay = true }

    func setVisible(_ visible: Bool) {
        isHidden = !visible
        widthConstraint.constant = visible ? ruleThickness : 0
        needsDisplay = true
    }

    func rebuildLines() {
        guard let editor else { return }
        let source = editor.string as NSString
        starts = [0]
        var cursor = 0
        while cursor < source.length {
            let end = NSMaxRange(source.lineRange(for: NSRange(location: cursor, length: 0)))
            guard end > cursor else { break }
            if end < source.length {
                starts.append(end)
            } else if source.length > 0 {
                let last = source.character(at: source.length - 1)
                if last == 10 || last == 13 || last == 0x2028 || last == 0x2029 { starts.append(end) }
            }
            cursor = end
        }
        updateWidth()
    }

    func updateWidth() {
        guard let editor else { return }
        let font = EditorTheme.font(size: editor.font?.pointSize ?? 14)
        let width = (String(starts.count) as NSString).size(withAttributes: [.font: font]).width + 24
        if ruleThickness != max(44, width) { ruleThickness = max(44, width) }
        needsDisplay = true
    }

    override func draw(_ rect: NSRect) {
        guard let editor, let layout = editor.layoutManager, let container = editor.textContainer else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: bounds.intersection(rect)).addClip()
        EditorTheme.background.setFill()
        bounds.fill()
        let visible = editor.visibleRect
        layout.ensureLayout(forBoundingRect: visible, in: container)
        let font = EditorTheme.font(size: editor.font?.pointSize ?? 14)
        let length = (editor.string as NSString).length
        let selected = editor.selectedRange().location
        let visibleGlyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let visibleCharacters = layout.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        var low = 0, high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= visibleCharacters.location { low = middle + 1 } else { high = middle }
        }
        for index in max(0, low - 1)..<starts.count {
            let start = starts[index]
            if start > NSMaxRange(visibleCharacters) { break }
            let lineRect: NSRect
            if start < length {
                let glyph = layout.glyphIndexForCharacter(at: start)
                lineRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
            } else {
                lineRect = layout.extraLineFragmentRect
            }
            let y = lineRect.minY + editor.textContainerOrigin.y
            if y + max(lineRect.height, font.pointSize + 4) < visible.minY { continue }
            if y > visible.maxY { break }
            let point = convert(NSPoint(x: 0, y: y), from: editor)
            let next = index + 1 < starts.count ? starts[index + 1] : length + 1
            let current = selected >= start && selected < next
            if current {
                EditorTheme.currentGutter.setFill()
                NSRect(x: 0, y: point.y, width: ruleThickness, height: max(lineRect.height, font.pointSize * 1.3)).fill()
            }
            let label = String(index + 1) as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: current ? EditorTheme.currentNumber : EditorTheme.gutter]
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 10, y: point.y + max(0, ((editor.font?.ascender ?? font.ascender) - font.ascender))), withAttributes: attributes)
        }
    }
}
