import AppKit
import SwiftUI

/// Resolves at draw time via NSAppearance — flips between two values when the
/// system appearance changes, no SwiftUI environment plumbing needed.
extension Color {
    init(light: Color, dark: Color) {
        self = Color(NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}

/// Shared visual tokens — radii, durations, colors that need to stay consistent.
enum Theme {

    // MARK: - Radii

    /// xs/s/m/l/xl scale: badge → cell → card → popover → panel.
    enum Radius {
        static let xs: CGFloat = 6
        static let s: CGFloat = 10
        static let m: CGFloat = 12
        static let l: CGFloat = 18
        static let xl: CGFloat = 28
    }

    // MARK: - Durations

    enum Duration {
        static let panelShow: CFTimeInterval = 0.16
        static let panelHide: CFTimeInterval = 0.11
        static let scrollSnap: Double = 0.2
        static let onboardingReveal: Double = 0.9
        static let clipboardPoll: Double = 0.4
        static let permissionsPoll: Double = 0.5
        static let pasteKeyDelay: UInt64 = 50_000_000  // 50 ms in nanoseconds
    }

    // MARK: - Palette

    enum Palette {
        /// macOS systemBlue (#007AFF).
        static let selection = Color(red: 0.0, green: 122.0/255.0, blue: 1.0)
    }

    // MARK: - Foreground (text & icons on Liquid Glass)

    /// Adaptive foreground tokens — black on light glass, white on dark glass.
    /// Light opacities are slightly lower than dark counterparts: pure black at
    /// 0.95 reads harsher on a light blur than white at 0.95 on a dark blur.
    enum Foreground {
        static let primary     = Color(light: .black.opacity(0.88), dark: .white.opacity(0.95))
        static let secondary   = Color(light: .black.opacity(0.72), dark: .white.opacity(0.85))
        static let tertiary    = Color(light: .black.opacity(0.58), dark: .white.opacity(0.70))
        static let muted       = Color(light: .black.opacity(0.45), dark: .white.opacity(0.55))
        static let placeholder = Color(light: .black.opacity(0.34), dark: .white.opacity(0.40))
    }

    // MARK: - Dividers

    enum Divider {
        static let strong = Color(light: .black.opacity(0.18), dark: .white.opacity(0.22))
        static let subtle = Color(light: .black.opacity(0.08), dark: .white.opacity(0.08))
    }

    // MARK: - Chip fills

    enum Chip {
        static let pinned = Color(light: .black.opacity(0.12), dark: .white.opacity(0.20))
        static let hover  = Color(light: .black.opacity(0.10), dark: .white.opacity(0.18))
        static let idle   = Color(light: .black.opacity(0.05), dark: .white.opacity(0.08))
    }

}
