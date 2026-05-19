import AppKit
import SwiftUI

/// Titled, closable NSPanel hosting a SwiftUI view. `.nonactivatingPanel` lets
/// the panel become key without flipping Crowy to `.regular` activation policy —
/// the paste panel uses the same trick. Combined with LSUIElement, this keeps
/// the Dock icon hidden whether the panel is open or closed.
final class AccessoryPanel: NSPanel {

    init<Content: View>(
        rootView: Content,
        title: String,
        contentSize: NSSize,
        resizable: Bool
    ) {
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .nonactivatingPanel]
        if resizable { styleMask.insert(.resizable) }

        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        self.title = title
        self.hidesOnDeactivate = false
        // Reused across show/hide cycles — without this, AppKit deallocates the
        // panel on close and our stored reference dangles.
        self.isReleasedWhenClosed = false

        let host = NSHostingView(rootView: rootView)
        host.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.contentView = container

        self.center()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show() {
        if !isVisible { center() }
        orderFrontRegardless()
        makeKey()
    }

    func hide() {
        orderOut(nil)
    }
}
