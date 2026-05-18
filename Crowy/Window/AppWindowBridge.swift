import SwiftUI

/// Single entry point for opening SwiftUI Window scenes from anywhere (AppKit,
/// other SwiftUI views, AppDelegate). Bakes in the activation-policy flip an
/// `.accessory` (menu-bar) app needs to do *before* `openWindow`, otherwise the
/// scene's window is created behind everything else.
///
/// Closures are installed by a hidden helper view inside `CrowyApp`'s `.commands`
/// block (the only place we can capture `@Environment(\.openWindow)` reliably at
/// app start). Calls before SwiftUI builds the menu are no-ops — defer with
/// `DispatchQueue.main.async` if invoking from `applicationDidFinishLaunching`.
@MainActor
final class AppWindowBridge {
    static let shared = AppWindowBridge()

    var openSettings: () -> Void = {}
    var openOnboarding: () -> Void = {}
}
