import SwiftUI

/// Keycap (HTML `<kbd>` style) used in shortcut hints.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.Foreground.tertiary)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.Chip.idle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.Divider.subtle, lineWidth: 1)
            )
    }
}

/// Row of keycaps with standard spacing — e.g. ⌘⌥V.
struct KeyCapRow: View {
    let keys: [String]

    init(_ keys: String...) {
        self.keys = keys
    }

    init(_ keys: [String]) {
        self.keys = keys
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(keys, id: \.self) { KeyCap(label: $0) }
        }
    }
}
