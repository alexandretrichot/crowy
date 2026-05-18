import SwiftUI

/// Placeholder shown when there are no clips: either history is empty or filters match nothing.
struct EmptyStateView: View {
    let kind: Kind

    enum Kind: Equatable {
        case noHistory(hotkey: HotkeyBinding)
        case noMatches
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.Foreground.placeholder)
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Foreground.tertiary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Foreground.muted)
                    .multilineTextAlignment(.center)
            }
            if case .noHistory(let hotkey) = kind {
                shortcutHint(for: hotkey)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Variants

    private var symbol: String {
        switch kind {
        case .noHistory: return "doc.on.clipboard"
        case .noMatches: return "magnifyingglass"
        }
    }

    private var title: String {
        switch kind {
        case .noHistory: return "Your clipboard is empty"
        case .noMatches: return "No matches"
        }
    }

    private var subtitle: String {
        switch kind {
        case .noHistory: return "Copy anything and it'll show up here."
        case .noMatches: return "Try removing or changing your filters."
        }
    }

    // MARK: - Shortcut hint (no-history only)

    private func shortcutHint(for hotkey: HotkeyBinding) -> some View {
        HStack(spacing: 6) {
            Text("Press")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Foreground.placeholder)
            KeyCapRow(hotkey.displayKeys)
            Text("to open Crowy anywhere.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Foreground.placeholder)
        }
    }
}
