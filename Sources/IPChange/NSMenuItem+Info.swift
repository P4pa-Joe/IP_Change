import AppKit

extension NSMenuItem {
    /// A read-only, non-highlighting menu row: a custom view bypasses
    /// NSMenu's default hover highlight and auto-disable (grayed out) text
    /// coloring, both of which only make sense for actionable items.
    static func infoItem(title: String) -> NSMenuItem {
        let item = NSMenuItem()

        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.sizeToFit()

        let horizontalPadding: CGFloat = 18
        let container = NSView(frame: NSRect(
            x: 0, y: 0,
            width: label.frame.width + horizontalPadding * 2,
            height: label.frame.height + 4
        ))
        label.frame.origin = NSPoint(x: horizontalPadding, y: 2)
        container.addSubview(label)

        item.view = container
        return item
    }
}
