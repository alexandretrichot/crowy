import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Paste-back: rewrite a clip to the system pasteboard, send ⌘V to the frontmost app.
///
/// The paste panel is `.nonactivatingPanel` and never activates Crowy, so the
/// user's previous app stays frontmost throughout. No re-activation needed —
/// we just write and post ⌘V, and the panel's hide animation runs in parallel.
///
/// Key constraints:
/// - We tag our writes with `PasteboardMarkers.internalUTI` so `InternalMarkerFilter`
///   skips them — otherwise we'd loop reinserting what we just pasted.
/// - CGEvent injection requires Accessibility trust; first use prompts the user.
@MainActor
final class PasteService {

    private let repository: ClipboardRepository
    private let onWillPaste: () -> Void
    private let onAccessibilityMissing: () -> Void

    init(
        repository: ClipboardRepository,
        onWillPaste: @escaping () -> Void,
        onAccessibilityMissing: @escaping () -> Void
    ) {
        self.repository = repository
        self.onWillPaste = onWillPaste
        self.onAccessibilityMissing = onAccessibilityMissing
    }

    func paste(_ clip: Clip) async {
        // Re-check trust at paste time: the user could have revoked Accessibility
        // since launch. Bailing here keeps the pasteboard untouched (their current
        // selection survives) and lets us surface a re-prompt.
        guard AXIsProcessTrusted() else {
            onAccessibilityMissing()
            return
        }

        do {
            let reps = try await repository.representations(of: clip.id)
            guard !reps.isEmpty else { return }

            writeToPasteboard(reps)
            onWillPaste()
            simulateCommandV()
        } catch {
            #if DEBUG
            print("PasteService error:", error)
            #endif
        }
    }

    // MARK: - Pasteboard write

    private func writeToPasteboard(_ reps: [ClipRepresentation]) {
        let pb = NSPasteboard.general
        pb.clearContents()

        let item = NSPasteboardItem()

        // Internal marker — empty data; only the type's presence matters.
        item.setData(
            Data(),
            forType: NSPasteboard.PasteboardType(PasteboardMarkers.internalUTI)
        )

        // All original reps preserved so the target app picks the best one
        // (PDF in Sketch, PNG in Photoshop, text in a terminal).
        for rep in reps {
            item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.uti))
        }

        pb.writeObjects([item])
    }

    // MARK: - Keystroke simulation

    /// Sends ⌘V via HID-level CGEvent. The target app must be frontmost before posting.
    private func simulateCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)

        let vKeyCode = CGKeyCode(kVK_ANSI_V)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand

        // `.cghidEventTap` injects at the lowest level; indistinguishable from a real keypress.
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
