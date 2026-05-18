import SwiftUI

@main
struct CrowyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Two SwiftUI Window scenes for the app's "regular" surfaces. The paste bar
        // stays on a custom `NSPanel` because no SwiftUI scene exposes `nonactivating`
        // / `floating` panel behavior (see `PastePanel`).
        //
        // `.restorationBehavior(.disabled)` keeps these windows from reopening on
        // every launch — undesired for a menu-bar app.

        Window("Settings", id: WindowID.settings) {
            SettingsHost(
                preferences: delegate.preferences,
                onHotkeyChange: delegate.handleHotkeyChange,
                onQuit: { NSApp.terminate(nil) }
            )
            .modifier(AccessoryAppWindow())
        }
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
        .commands {
            // Replaces the standard "Settings…" item so Cmd+, opens our Window scene,
            // and stashes `openWindow` actions for AppKit-side callers (see AppWindowBridge).
            CommandGroup(replacing: .appSettings) {
                AppCommands()
            }
        }

        Window("Welcome to Crowy", id: WindowID.onboarding) {
            OnboardingHost(
                permissions: delegate.permissions,
                onComplete: delegate.completeOnboarding
            )
            .modifier(AccessoryAppWindow())
        }
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
    }
}

// MARK: - Window IDs

enum WindowID {
    static let settings = "settings"
    static let onboarding = "onboarding"
}

// MARK: - Hosts

private struct SettingsHost: View {
    @Bindable var preferences: Preferences
    let onHotkeyChange: (HotkeyBinding) -> Void
    let onQuit: () -> Void

    var body: some View {
        SettingsView(
            preferences: preferences,
            onHotkeyChange: onHotkeyChange,
            onQuit: onQuit
        )
    }
}

private struct OnboardingHost: View {
    @Bindable var permissions: PermissionsManager
    let onComplete: () -> Void

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        OnboardingView(
            permissions: permissions,
            onDismiss: { dismissWindow(id: WindowID.onboarding) }
        )
        // Fires on red-X, Cmd+W, or `dismissWindow` — all paths converge on "show panel".
        .onDisappear { onComplete() }
    }
}

// MARK: - Commands

/// Lives in the app menu (replacing the standard Settings item). Two jobs:
///   1. Bind Cmd+, to open the settings window.
///   2. Capture `openWindow` so any caller (PasteBarView, AppDelegate) can open
///      our SwiftUI windows through `AppWindowBridge`, with the activation-policy
///      flip baked in.
private struct AppCommands: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            AppWindowBridge.shared.openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
        .onAppear {
            // Policy flip must happen *before* openWindow — otherwise the window
            // is created behind everything (the `.accessory` app can't surface
            // a new window). Flipping after-the-fact (e.g. in a view's onAppear)
            // doesn't bring an already-misplaced window forward.
            AppWindowBridge.shared.openSettings = {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: WindowID.settings)
            }
            AppWindowBridge.shared.openOnboarding = {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: WindowID.onboarding)
            }
        }
    }
}

// MARK: - Activation policy

/// `.accessory` makes Crowy menu-bar-only (no Dock icon). The forward flip happens
/// in `AppWindowBridge.openSettings/openOnboarding` before `openWindow`. This
/// modifier handles the *reverse* — back to `.accessory` once no titled window is
/// visible (so the Dock icon disappears when the user closes settings).
private struct AccessoryAppWindow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onDisappear {
                // The paste panel is borderless, so it doesn't count as "a window
                // that wants Dock presence" — only titled windows do.
                let hasOtherTitledWindow = NSApp.windows.contains { window in
                    window.isVisible && window.styleMask.contains(.titled)
                }
                if !hasOtherTitledWindow {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
    }
}
