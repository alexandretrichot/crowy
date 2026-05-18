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

    /// Triggers the system prompt and also opens System Settings on the right pane.
    func requestAccessibility() {
        // System prompt — fires once per process, only if the user never answered.
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)

        // Also open Settings: the prompt can be missed if the app is in background.
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
