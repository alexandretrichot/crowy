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

    /// Resets the stale TCC entry, then triggers the system prompt — which is
    /// the only reliable way to both *register* the app with TCC (so it shows
    /// up in the Accessibility list) and present a UI. Plain
    /// `AXIsProcessTrusted()` queries TCC but doesn't add the app to the list,
    /// and a bare `NSWorkspace.open(Settings)` lands the user on an empty pane
    /// with no Crowy entry to toggle.
    ///
    /// The reset is needed because ad-hoc signing means every build has a
    /// different cdhash: TCC silently invalidates the prior grant while
    /// leaving a stale checked entry in System Settings that no toggle can
    /// fix. Wiping the entry first means the prompt fires fresh and the user
    /// gets a clean grant flow. The prompt itself carries an "Open System
    /// Settings" button — letting Apple's prompt drive the flow avoids
    /// stacking two competing UIs.
    ///
    /// Only called when permission is currently missing (gated by the Grant
    /// button visibility and `onAccessibilityMissing`), so a valid grant is
    /// never wiped.
    func requestAccessibility() {
        resetStaleTCCEntry()

        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)

        startPolling()
    }

    private func resetStaleTCCEntry() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", bundleID]
        // Silence tccutil's stdout/stderr — its diagnostics aren't useful here
        // and we don't want them in the app's console.
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // Non-fatal: if tccutil is missing or fails, Settings still works
            // the long way (user manually toggles or removes and re-adds).
        }
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
