import AppKit
import SwiftUI

/// SwiftUI bridge to NSTextView. Single-line with inline `PillTextAttachment`s; `tokens` is the source of truth.
struct SearchBarTextView: NSViewRepresentable {

    @Binding var tokens: [SearchBarToken]
    @Binding var isFocused: Bool
    let placeholder: String
    let onEnter: () -> Void
    let onEscape: () -> Void

    /// Returns true if the arrow was consumed; false lets NSTextView handle cursor nav
    let onArrow: (ArrowDirection) -> Bool

    enum ArrowDirection { case up, down }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SearchBarHostingView {
        let host = SearchBarHostingView()
        host.textView.delegate = context.coordinator
        context.coordinator.textView = host.textView
        host.textView.string = ""
        // textDidBeginEditing fires only on first edit, not on FR gain via click — use this hook instead
        host.textView.onFirstResponderChange = { [weak coordinator = context.coordinator] focused in
            coordinator?.handleFirstResponderChange(focused)
        }
        return host
    }

    func updateNSView(_ host: SearchBarHostingView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncTokensIfNeeded(tokens)
        context.coordinator.syncFocusIfNeeded(isFocused, host: host)
        context.coordinator.syncPlaceholder(placeholder)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SearchBarTextView
        weak var textView: NSTextView?

        /// Prevents the textDidChange ↔ updateNSView ping-pong
        var isUpdatingFromSwiftUI = false

        init(_ parent: SearchBarTextView) {
            self.parent = parent
        }

        // MARK: - Sync (SwiftUI → NSTextView)

        func syncTokensIfNeeded(_ tokens: [SearchBarToken]) {
            guard let textView else { return }
            let currentTokens = SearchBarTokenCoder.extract(from: textView.attributedString())
            if currentTokens == tokens { return }
            isUpdatingFromSwiftUI = true
            defer { isUpdatingFromSwiftUI = false }
            textView.textStorage?.setAttributedString(SearchBarTokenCoder.build(from: tokens))
            // Re-arm typingAttributes so subsequent chars don't inherit the last insert's attrs (e.g. an attachment → black)
            textView.typingAttributes = SearchBarTokenCoder.textAttributes
            let end = textView.string.utf16.count
            textView.setSelectedRange(NSRange(location: end, length: 0))
        }

        func syncFocusIfNeeded(_ shouldBeFocused: Bool, host: SearchBarHostingView) {
            guard let textView, let window = textView.window else { return }
            let currentlyFocused = (window.firstResponder === textView)
            if shouldBeFocused == currentlyFocused { return }
            if shouldBeFocused {
                window.makeFirstResponder(textView)
            } else if currentlyFocused {
                window.makeFirstResponder(nil)
            }
        }

        func syncPlaceholder(_ placeholder: String) {
            (textView as? PlaceholderTextView)?.placeholderString = placeholder
        }

        // MARK: - NSTextViewDelegate (NSTextView → SwiftUI)

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI, let textView else { return }
            // Any mutation can let typingAttributes drift to system defaults or a neighbour attachment's attrs — force ours
            textView.typingAttributes = SearchBarTokenCoder.textAttributes
            let newTokens = SearchBarTokenCoder.extract(from: textView.attributedString())
            if newTokens == parent.tokens { return }
            parent.tokens = newTokens
        }

        /// Called from PlaceholderTextView's becomeFirstResponder/resignFirstResponder — earlier than textDidBegin/EndEditing
        func handleFirstResponderChange(_ focused: Bool) {
            if parent.isFocused != focused {
                parent.isFocused = focused
            }
        }

        /// NSTextView re-infers typingAttributes on selection change; when empty (after clear or near an attachment) it falls back to system defaults (black text in light mode)
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdatingFromSwiftUI, let textView else { return }
            textView.typingAttributes = SearchBarTokenCoder.textAttributes
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onEnter()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            case #selector(NSResponder.moveUp(_:)):
                return parent.onArrow(.up)
            case #selector(NSResponder.moveDown(_:)):
                return parent.onArrow(.down)
            default:
                return false
            }
        }
    }
}

// MARK: - PlaceholderTextView

/// NSTextView with placeholder drawing, copy/paste that round-trips pills via a custom pasteboard type, and an early first-responder callback (earlier than textDidBeginEditing, which fires only on first edit).
final class PlaceholderTextView: NSTextView {
    var placeholderString: String = "" { didSet { needsDisplay = true } }

    var onFirstResponderChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFirstResponderChange?(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFirstResponderChange?(false) }
        return ok
    }

    // MARK: - Placeholder

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        // Same attrs as typed runs so paragraph style and baselineOffset match
        var attrs = SearchBarTokenCoder.textAttributes
        attrs[.foregroundColor] = NSColor.placeholderTextColor
        let inset = textContainerInset
        let lineFragmentPadding = textContainer?.lineFragmentPadding ?? 0
        let placeholderRect = NSRect(
            x: inset.width + lineFragmentPadding,
            y: inset.height,
            width: bounds.width,
            height: bounds.height
        )
        (placeholderString as NSString).draw(in: placeholderRect, withAttributes: attrs)
    }

    // MARK: - Copy / Cut / Paste

    override func copy(_ sender: Any?) {
        writeSelectionToPasteboard(NSPasteboard.general)
    }

    override func cut(_ sender: Any?) {
        writeSelectionToPasteboard(NSPasteboard.general)
        if let storage = textStorage {
            let range = selectedRange()
            storage.replaceCharacters(in: range, with: "")
            didChangeText()
        }
    }

    /// Token round-trip if our internal pasteboard type is present, otherwise plain-text fallback. Cmd+V here pastes into the search bar, not back to the source app.
    override func paste(_ sender: Any?) {
        let pboard = NSPasteboard.general
        if pboard.types?.contains(SearchBarTokenCoder.pasteboardType) == true,
           let data = pboard.data(forType: SearchBarTokenCoder.pasteboardType),
           let tokens = try? JSONDecoder().decode([SearchBarToken].self, from: data) {
            insertTokens(tokens)
            return
        }
        if let plain = pboard.string(forType: .string) {
            insertText(plain, replacementRange: selectedRange())
        }
    }

    private func insertTokens(_ tokens: [SearchBarToken]) {
        guard let storage = textStorage else { return }
        let attr = SearchBarTokenCoder.build(from: tokens)
        storage.replaceCharacters(in: selectedRange(), with: attr)
        typingAttributes = SearchBarTokenCoder.textAttributes
        didChangeText()
    }

    /// Writes 3 representations: JSON tokens (round-trip), plain text (cross-app), and an internal marker so InternalMarkerFilter rejects our own copies
    private func writeSelectionToPasteboard(_ pboard: NSPasteboard) {
        let range = selectedRange()
        guard range.length > 0 else { return }
        let selectedAttr = attributedString().attributedSubstring(from: range)
        let tokens = SearchBarTokenCoder.extract(from: selectedAttr)
        guard !tokens.isEmpty else { return }

        pboard.clearContents()
        if let data = try? JSONEncoder().encode(tokens) {
            pboard.setData(data, forType: SearchBarTokenCoder.pasteboardType)
        }
        pboard.setString(SearchBarTokenCoder.renderPlainText(from: tokens), forType: .string)
        pboard.setData(Data(), forType: NSPasteboard.PasteboardType(PasteboardMarkers.internalUTI))
    }
}

// MARK: - Hosting NSView

final class SearchBarHostingView: NSView {
    let textView: PlaceholderTextView

    override init(frame frameRect: NSRect) {
        let container = NSTextContainer(containerSize: NSSize(width: 1_000_000, height: 1_000_000))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)

        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)

        textView = PlaceholderTextView(frame: .zero, textContainer: container)
        Self.configure(textView)

        super.init(frame: frameRect)
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private static func configure(_ tv: PlaceholderTextView) {
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = true              // required for attachments
        tv.usesFontPanel = false
        tv.usesRuler = false
        tv.allowsUndo = false
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.textColor = .textColor
        tv.insertionPointColor = .textColor
        // No vertical inset — paragraph style's lineHeight handles spacing
        tv.textContainerInset = NSSize(width: 0, height: 0)
        // typingAttributes is the real source of truth; NSTextView ignores `textColor` past first setup
        tv.typingAttributes = SearchBarTokenCoder.textAttributes
        tv.isContinuousSpellCheckingEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false

        // Single-line: no wrap, no vertical expansion
        let h = SearchBarTokenCoder.lineHeight
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: h)
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = false
        if let container = tv.textContainer {
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: h)
            container.widthTracksTextView = false
        }
    }
}
