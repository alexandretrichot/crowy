import AppKit

// MARK: - PillTextAttachment

/// NSTextAttachment carrying its ClipFilter. Cross-process round-trip drops the filter (no NSCoding); within-app uses the object pointer.
final class PillTextAttachment: NSTextAttachment {
    let filter: ClipFilter

    init(filter: ClipFilter) {
        self.filter = filter
        super.init(data: nil, ofType: nil)
        self.attachmentCell = PillAttachmentCell(filter: filter)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }
}

// MARK: - PillAttachmentCell

/// Cocoa rendering of a pill (capsule + icon + label). Cell occupies the full ambient lineHeight so the pill aligns with the text cursor; the visual is inset via `capsuleInsetY`.
final class PillAttachmentCell: NSTextAttachmentCell {

    let filter: ClipFilter

    // MARK: - Style

    nonisolated private static var labelAttrs: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.98),
        ]
    }

    nonisolated private static let horizontalPadding: CGFloat = 8
    nonisolated private static let iconSize: CGFloat = 12
    nonisolated private static let iconLabelGap: CGFloat = 5

    /// Vertical inset of the visible capsule inside the full-lineHeight cell
    nonisolated private static let capsuleInsetY: CGFloat = 2

    /// External horizontal margin separating the pill from neighbours; the visible capsule is inset by this on both sides
    nonisolated private static let outerGap: CGFloat = 4

    init(filter: ClipFilter) {
        self.filter = filter
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("not supported") }

    // MARK: - Layout

    override nonisolated func cellSize() -> NSSize {
        let labelSize = (filter.pillLabel as NSString).size(withAttributes: Self.labelAttrs)
        let iconWidth: CGFloat = hasIcon ? Self.iconSize + Self.iconLabelGap : 0
        return NSSize(
            width: labelSize.width + iconWidth + Self.horizontalPadding * 2 + Self.outerGap * 2,
            height: SearchBarTokenCoder.lineHeight
        )
    }

    /// Offset aligns the cell bottom with the line bottom (accounting for paragraph extra leading) and matches text runs' `textBaselineOffset`
    override nonisolated func cellBaselineOffset() -> NSPoint {
        let ambient = NSFont.systemFont(ofSize: 13)
        let naturalHeight = ambient.ascender - ambient.descender
        let extraLeading = (SearchBarTokenCoder.lineHeight - naturalHeight) / 2
        return NSPoint(
            x: 0,
            y: ambient.descender - extraLeading + SearchBarTokenCoder.textBaselineOffset
        )
    }

    // MARK: - Draw

    override nonisolated func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let capsuleFrame = NSRect(
            x: cellFrame.minX + Self.outerGap,
            y: cellFrame.minY,
            width: cellFrame.width - Self.outerGap * 2,
            height: cellFrame.height
        )
        let visibleFrame = capsuleFrame.insetBy(dx: 0.5, dy: Self.capsuleInsetY)
        let radius = visibleFrame.height / 2

        let bgPath = NSBezierPath(roundedRect: visibleFrame,
                                  xRadius: radius, yRadius: radius)
        NSColor.white.withAlphaComponent(0.16).setFill()
        bgPath.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        bgPath.lineWidth = 0.5
        bgPath.stroke()

        var contentX = capsuleFrame.minX + Self.horizontalPadding

        if let icon = pillIcon {
            let iconRect = NSRect(
                x: contentX,
                y: cellFrame.midY - Self.iconSize / 2,
                width: Self.iconSize,
                height: Self.iconSize
            )
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
            contentX += Self.iconSize + Self.iconLabelGap
        }

        let label = filter.pillLabel as NSString
        let labelSize = label.size(withAttributes: Self.labelAttrs)
        let labelRect = NSRect(
            x: contentX,
            y: cellFrame.midY - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        label.draw(in: labelRect, withAttributes: Self.labelAttrs)
    }

    // MARK: - Icon

    nonisolated private var hasIcon: Bool { pillIcon != nil }

    nonisolated private var pillIcon: NSImage? {
        switch filter {
        case .text:
            return tintedSymbol("magnifyingglass")
        case .time:
            return tintedSymbol("calendar")
        case .kind(let kind):
            return tintedSymbol(kind.sfSymbol)
        case .app(let bundleID, _):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return tintedSymbol("app")
            }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    nonisolated private func tintedSymbol(_ name: String) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: Self.iconSize, weight: .semibold)
            .applying(.init(paletteColors: [NSColor.white.withAlphaComponent(0.8)]))
        return base.withSymbolConfiguration(config)
    }
}
