import AppKit

/// Reserve room for a non-overlay scrollbar without squeezing the tab buttons.
final class TabScrollView: NSScrollView {
    private var rowHeight: NSLayoutConstraint!
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        rowHeight = heightAnchor.constraint(equalToConstant: 43)
        rowHeight.isActive = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override func tile() {
        super.tile()
        guard let rowHeight, frame.height > 0 else { return }
        let height = 43 + max(0, frame.height - contentSize.height)
        if abs(rowHeight.constant - height) > 0.5 { rowHeight.constant = height }
    }
}
