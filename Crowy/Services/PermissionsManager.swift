import AppKit
import ApplicationServices

/// Tracks Accessibility permission (needed for the ⌘V CGEvent). Polls after a
/// request so the onboarding window closes as soon as the user grants it.
@MainActor
@Observable
final class PermissionsManager {

    var isAccessibilityGranted: Bool

    @ObservationIgnored
    private var pollTimer: Timer?

    init() {
        self.isAccessibilityGranted = AXIsProcessTrusted()
    }

    /// Opens System Settings on the Accessibility pane. We deliberately don't
    /// trigger the system prompt: it's one-shot (won't fire again if the user
    /// dismissed or denied it once) and showing it alongside Settings just
    /// stacks two competing UIs. Settings alone is reliable and re-tryable —
    /// the app is already registered with TCC via `AXIsProcessTrusted()` in
    /// `init`, so it appears in the list ready to toggle.
    func requestAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        startPolling()
    }

    /// Re-checks immediately — call when the window comes back to front.
    func refresh() {
        isAccessibilityGranted = AXIsProcessTrusted()
        if isAccessibilityGranted { stopPolling() }
    }

    // MARK: - Polling

    /// No system callback exists for AX trust changes, so we poll at 0.5s.
    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let granted = AXIsProcessTrusted()
                if granted != self.isAccessibilityGranted {
                    self.isAccessibilityGranted = granted
                }
                if granted {
                    self.stopPolling()
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
