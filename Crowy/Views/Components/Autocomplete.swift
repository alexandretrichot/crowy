import SwiftUI

/// Generic controlled dropdown: parent owns state (highlight, dismissed, focus)
/// and drives keyboard; this view only renders and handles hover/tap.
struct Autocomplete<Item: Hashable, Row: View>: View {
    let items: [Item]

    @Binding var highlightedIndex: Int
    @Binding var dismissed: Bool

    let anchorFocused: Bool

    let onSelect: (Item) -> Void
    @ViewBuilder let row: (Item, Bool) -> Row

    var isVisible: Bool {
        anchorFocused && !dismissed && !items.isEmpty
    }

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element) { index, item in
                    row(item, index == highlightedIndex)
                        .contentShape(Rectangle())
                        .onHover { hovered in
                            if hovered { highlightedIndex = index }
                        }
                        .onTapGesture { onSelect(item) }
                }
            }
            .padding(5)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
            )
            .glassEffectTransition(.identity)
            .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
            .fixedSize()
            .transition(.opacity.combined(with: .offset(y: -4)))
        }
    }
}
