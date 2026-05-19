import AppKit
import SwiftUI
import QuartzCore

/// Floating non-activating panel pinned to the bottom of the main screen's visible frame.
/// Slides up via a `CATransform3D` on the contentView's layer (the window itself stays put,
/// so the material blur samples a stable rect). Becomes key without activating its app.
final class PastePanel: NSPanel {

    static let barHeight: CGFloat = 330
    static let sideMargin: CGFloat = 8
    static let bottomMargin: CGFloat = 8
    static let windowHeight: CGFloat = barHeight
    private let showDuration: CFTimeInterval = Theme.Duration.panelShow
    private let hideDuration: CFTimeInterval = Theme.Duration.panelHide

    private var isAnimating = false

    /// Layer-backed container we translate vertically. Hosts the SwiftUI hosting view.
    private let slideContainer: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer = CALayer()
        return v
    }()

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: Self.onScreenFrame(),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isFloatingPanel = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovable = false
        self.titlebarAppearsTransparent = true
        self.animationBehavior = .none

        let host = NSHostingView(rootView: rootView)
        host.translatesAutoresizingMaskIntoConstraints = false
        slideContainer.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: slideContainer.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: slideContainer.trailingAnchor),
            host.topAnchor.constraint(equalTo: slideContainer.topAnchor),
            host.bottomAnchor.constraint(equalTo: slideContainer.bottomAnchor),
        ])
        self.contentView = slideContainer

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResignKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Backspace/Delete fallback routed at the panel level — `.onKeyPress(.delete)`
    /// is unreliable for Backspace in SwiftUI on macOS. Fires only when no
    /// NSTextView holds first responder (i.e. SearchBar isn't active).
    var onDeleteOutsideTextEditing: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])

        // Cmd+, → open Settings. Replaces the native menu shortcut that an
        // `.accessory` app without a menu bar can't provide.
        if event.charactersIgnoringModifiers == ",", mods == [.command] {
            AppWindowBridge.shared.openSettings()
            return
        }

        let isDeleteKey = event.keyCode == 51 || event.keyCode == 117
        let firstResponderIsText = (firstResponder is NSTextView)
        if isDeleteKey, mods.isEmpty, !firstResponderIsText,
           let handler = onDeleteOutsideTextEditing {
            handler()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Frames

    /// Picks the screen under the mouse — standard pattern for HUD utilities
    /// (Spotlight/Raycast/Alfred). Robust against screen unplug since
    /// `NSScreen.screens` is refreshed by AppKit on configuration changes.
    private static func screen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let s = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return s
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    static func onScreenFrame() -> NSRect {
        let v = screen().visibleFrame
        return NSRect(
            x: v.origin.x,
            y: v.origin.y,
            width: v.width,
            height: windowHeight
        )
    }

    // MARK: - Show / hide

    func show(animated: Bool = true) {
        // Window jumps straight to its final on-screen rect — no frame animation, so
        // the window server has no overdraw and the material blur samples a stable rect.
        setFrame(Self.onScreenFrame(), display: true)
        orderFrontRegardless()
        makeKey()

        guard let layer = slideContainer.layer else { return }

        if !animated {
            layer.removeAllAnimations()
            layer.transform = CATransform3DIdentity
            return
        }

        // Start translated down by `barHeight` (offscreen below the window), animate to identity.
        let from = CATransform3DMakeTranslation(0, -Self.windowHeight, 0)
        let to = CATransform3DIdentity

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = to
        CATransaction.commit()

        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = NSValue(caTransform3D: from)
        anim.toValue = NSValue(caTransform3D: to)
        anim.duration = showDuration
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0) // snappy easeOut
        layer.add(anim, forKey: "slide")
    }

    func hide(animated: Bool = true) {
        guard isVisible, !isAnimating else { return }
        isAnimating = true

        guard animated, let layer = slideContainer.layer else {
            orderOut(nil)
            isAnimating = false
            return
        }

        let to = CATransform3DMakeTranslation(0, -Self.windowHeight, 0)
        let from = CATransform3DIdentity

        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = NSValue(caTransform3D: from)
        anim.toValue = NSValue(caTransform3D: to)
        anim.duration = hideDuration
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.55, 0, 0.85, 0.3) // snappy easeIn
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
            self.slideContainer.layer?.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.slideContainer.layer?.transform = CATransform3DIdentity
            CATransaction.commit()
            self.isAnimating = false
        }
        layer.add(anim, forKey: "slide")
        CATransaction.commit()
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    @objc private func handleResignKey() {
        guard isVisible, !isAnimating else { return }
        hide(animated: true)
    }
}
