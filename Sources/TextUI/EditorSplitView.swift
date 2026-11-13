import AppKit

/// The native controller owns divider dragging and collapsed pane constraints.
final class EditorSplitView: NSSplitView {
    private var editorItem: NSSplitViewItem?
    private var previewItem: NSSplitViewItem?
    private var fraction: CGFloat = 0.65
    private var arranging = false
    private var observer: NSObjectProtocol?
    var minimumEditorWidth: CGFloat = 320 {
        didSet { editorItem?.minimumThickness = minimumEditorWidth }
    }
    var previewVisible = false {
        didSet {
            guard let previewItem else { return }
            arranging = true
            previewItem.isCollapsed = !previewVisible
            arranging = false
            arrange()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isVertical = true; dividerStyle = .thin
        setAccessibilityLabel("Quelltext und Vorschau")
        observer = NotificationCenter.default.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: self, queue: .main) { [weak self] notification in
            self?.splitViewDidResizeSubviews(notification)
        }
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func configure(editor: NSView, preview: NSView, controller: NSSplitViewController) {
        controller.splitView = self
        let editorController = NSViewController(); editorController.view = editor
        let previewController = NSViewController(); previewController.view = preview
        let source = NSSplitViewItem(viewController: editorController)
        source.minimumThickness = minimumEditorWidth
        source.preferredThicknessFraction = fraction
        let rendered = NSSplitViewItem(viewController: previewController)
        rendered.minimumThickness = 240
        rendered.canCollapse = false
        rendered.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        rendered.isCollapsed = true
        editorItem = source; previewItem = rendered
        controller.addSplitViewItem(source); controller.addSplitViewItem(rendered)
        _ = controller.view
    }

    func arrange() {
        guard previewVisible, arrangedSubviews.count == 2, bounds.width > 0, !arranging else { return }
        arranging = true
        defer { arranging = false }
        let width = bounds.width - dividerThickness
        let position = min(max(minimumEditorWidth, width * fraction), width - 240)
        setPosition(position, ofDividerAt: 0)
    }
    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !arranging, previewVisible, arrangedSubviews.count == 2, bounds.width > dividerThickness else { return }
        fraction = arrangedSubviews[0].frame.width / (bounds.width - dividerThickness)
    }
}
