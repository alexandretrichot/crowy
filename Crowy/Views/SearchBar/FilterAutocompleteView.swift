import SwiftUI

struct FilterAutocompleteView: View {
    let suggestions: [ClipFilter]

    @Binding var highlightedIndex: Int
    @Binding var dismissed: Bool

    let anchorFocused: Bool
    let onSelect: (ClipFilter) -> Void

    @Environment(AppIconProvider.self) private var iconProvider

    var body: some View {
        Autocomplete(
            items: suggestions,
            highlightedIndex: $highlightedIndex,
            dismissed: $dismissed,
            anchorFocused: anchorFocused,
            onSelect: onSelect
        ) { filter, isHighlighted in
            FilterSuggestionRow(
                filter: filter,
                isHighlighted: isHighlighted,
                iconProvider: iconProvider,
                showDividerBelow: shouldShowDividerAfter(filter)
            )
        }
    }

    private func shouldShowDividerAfter(_ filter: ClipFilter) -> Bool {
        guard let i = suggestions.firstIndex(of: filter),
              i < suggestions.count - 1 else { return false }
        return filter.category != suggestions[i + 1].category
    }
}

// MARK: - Row

private struct FilterSuggestionRow: View {
    let filter: ClipFilter
    let isHighlighted: Bool
    let iconProvider: AppIconProvider
    let showDividerBelow: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                icon.frame(width: 16, height: 16)
                Text(filter.pillLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Foreground.primary)
                Spacer(minLength: 16)
                Text(filter.category.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(isHighlighted ? 0.5 : 0.3))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(minWidth: 220, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.xs, style: .continuous)
                    .fill(isHighlighted ? Color.primary.opacity(0.16) : Color.clear)
            )

            if showDividerBelow {
                Rectangle()
                    .fill(Theme.Divider.subtle)
                    .frame(height: 1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch filter {
        case .text:
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Foreground.tertiary)
        case .time:
            Image(systemName: "calendar")
                .foregroundStyle(Theme.Foreground.tertiary)
        case .kind(let kind):
            Image(systemName: kind.sfSymbol)
                .foregroundStyle(Theme.Foreground.tertiary)
        case .app(let bundleID, _):
            if let nsImage = iconProvider.icon(forBundleID: bundleID) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app")
                    .foregroundStyle(Theme.Foreground.tertiary)
            }
        }
    }
}

// MARK: - Category

extension ClipFilter {
    fileprivate enum Category: String {
        case text, kind, time, app
        var label: String {
            switch self {
            case .text: return "Search"
            case .kind: return "Type"
            case .time: return "Date"
            case .app:  return "App"
            }
        }
    }

    fileprivate var category: Category {
        switch self {
        case .text: return .text
        case .kind: return .kind
        case .time: return .time
        case .app:  return .app
        }
    }
}
