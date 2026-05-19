import AppKit
import SwiftUI

@main
struct CrowyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Stub: SwiftUI App requires a Scene. Nothing opens this — it just lets
        // the app build.
        WindowGroup(id: "stub") {
            EmptyView()
        }
        .defaultLaunchBehavior(.suppressed)

        // `Window` rather than `Settings`: on macOS 26, `Settings { }` ships with
        // cosmetic bugs (squared corners, traffic lights mispositioned, broken
        // NavigationSplitView layout). A plain `Window` gets the proper Liquid
        // Glass treatment.
        Window("Crowy — Settings", id: WindowID.settings) {
            SettingsHost(
                preferences: delegate.preferences,
                onHotkeyChange: delegate.handleHotkeyChange,
                onQuit: { NSApp.terminate(nil) }
            )
        }
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
    }
}

enum WindowID {
    static let settings = "settings"
}

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
