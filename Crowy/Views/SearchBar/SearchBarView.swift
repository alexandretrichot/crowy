import SwiftUI

/// Intermediate node in the focus hierarchy: receives `isActive` from the parent and owns `activeChild` for its own popover.
/// External FR loss (panel hide, click outside) propagates `isActive = false` to the parent via the binding.
struct SearchBarView: View {

    // MARK: - Focus hierarchy

    @Binding var isActive: Bool

    private enum SearchChild: Hashable {
        case filterPopover
    }

    @State private var activeChild: SearchChild?

    /// True ⇒ NSTextView is first responder, keys go to it
    private var isLeaf: Bool { isActive && activeChild == nil }

    // MARK: - Bindings

    @Binding var tokens: [SearchBarToken]

    // MARK: - Inputs

    let placeholder: String
    let pinnedFilters: [ClipFilter]

    let autocompleteSuggestions: [ClipFilter]

    // MARK: - Callbacks

    let onFilterPicked: (ClipFilter) -> Void

    let onClear: () -> Void

    let onEnterIdle: () -> Void

    let onEscapeIdle: () -> Void

    let loadApps: () async -> [SourceAppInfo]

    // MARK: - State (autocomplete dropdown)

    @State private var autocompleteIndex: Int = 0
    @State private var autocompleteDismissed: Bool = false

    private var isAutocompleteVisible: Bool {
        isLeaf && !autocompleteDismissed && !autocompleteSuggestions.isEmpty
    }

    // MARK: - Body

    var body: some View {
        capsule
            .overlayPreferenceValue(SearchBarTextFieldBoundsKey.self) { anchor in
                GeometryReader { proxy in
                    if let anchor, isAutocompleteVisible {
                        let rect = proxy[anchor]
                        FilterAutocompleteView(
                            suggestions: autocompleteSuggestions,
                            highlightedIndex: $autocompleteIndex,
                            dismissed: $autocompleteDismissed,
                            anchorFocused: isLeaf,
                            onSelect: { filter in
                                onFilterPicked(filter)
                                // Keep focus on the textfield after pick
                                isActive = true
                                activeChild = nil
                            }
                        )
                        .offset(x: rect.minX, y: rect.maxY + 6)
                    }
                }
                // Without this, the full-bleed GeometryReader swallows clicks meant for the textfield
                .allowsHitTesting(isAutocompleteVisible)
                .animation(
                    .spring(response: 0.22, dampingFraction: 0.85),
                    value: isAutocompleteVisible
                )
            }
            .onChange(of: tokens.freeText) { _, _ in
                autocompleteIndex = 0
                autocompleteDismissed = false
            }
    }

    private var capsule: some View {
        HStack(alignment: .center, spacing: 8) {
            magnifier
            textField
            if !tokens.isEmpty { clearButton }
            filterButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color(
                    light: .black.opacity(isLeaf ? 0.08 : 0.04),
                    dark:  .black.opacity(isLeaf ? 0.32 : 0.22)
                ))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(isLeaf ? 0.28 : 0.06),
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.18), value: isLeaf)
        // No spring on `tokens.isEmpty`: an under-damped spring overshoots the clearButton scale and jiggles HStack height by 1pt
    }

    // MARK: - Pieces

    private var magnifier: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(isLeaf ? 0.75 : 0.5))
            .animation(.easeOut(duration: 0.15), value: isLeaf)
    }

    private var textField: some View {
        SearchBarTextView(
            tokens: $tokens,
            isFocused: textFieldFocusBinding,
            placeholder: placeholder,
            onEnter: handleEnter,
            onEscape: handleEscape,
            onArrow: handleArrow
        )
        .frame(height: SearchBarTokenCoder.lineHeight)
        .anchorPreference(key: SearchBarTextFieldBoundsKey.self, value: .bounds) { $0 }
    }

    private var clearButton: some View {
        IconButton(systemName: "xmark.circle.fill", size: 12, tint: 0.5, action: onClear)
            .transition(.opacity.combined(with: .scale(scale: 0.7)))
    }

    private var filterButton: some View {
        IconButton(
            systemName: "line.3.horizontal.decrease",
            size: 12,
            weight: .semibold,
            tint: activeChild == .filterPopover ? 0.85 : 0.6
        ) {
            activeChild = (activeChild == .filterPopover) ? nil : .filterPopover
        }
        .popover(isPresented: filterPopoverBinding, arrowEdge: .bottom) {
            FilterPickerView(
                alreadyPinned: pinnedFilters,
                loadApps: loadApps,
                onSelect: { filter in
                    onFilterPicked(filter)
                    activeChild = nil
                }
            )
        }
    }

    // MARK: - Coordinated bindings

    /// Translates NSTextView FR gain/loss into `isActive`/`activeChild` updates. When FR loss is caused by a child taking it (popover), keep `isActive` true.
    private var textFieldFocusBinding: Binding<Bool> {
        Binding(
            get: { isLeaf },
            set: { newValue in
                if newValue {
                    isActive = true
                    activeChild = nil
                } else if activeChild == nil {
                    isActive = false
                }
            }
        )
    }

    private var filterPopoverBinding: Binding<Bool> {
        Binding(
            get: { activeChild == .filterPopover },
            set: { presented in
                activeChild = presented ? .filterPopover : nil
            }
        )
    }

    // MARK: - Keyboard routing (NSTextView callbacks)

    private func handleEnter() {
        if isAutocompleteVisible {
            let safe = max(0, min(autocompleteIndex, autocompleteSuggestions.count - 1))
            onFilterPicked(autocompleteSuggestions[safe])
            autocompleteIndex = 0
            autocompleteDismissed = false
            return
        }
        onEnterIdle()
    }

    private func handleEscape() {
        if isAutocompleteVisible {
            autocompleteDismissed = true
            return
        }
        onEscapeIdle()
    }

    private func handleArrow(_ direction: SearchBarTextView.ArrowDirection) -> Bool {
        guard isAutocompleteVisible else { return false }
        let count = autocompleteSuggestions.count
        switch direction {
        case .up: autocompleteIndex = (autocompleteIndex - 1 + count) % count
        case .down: autocompleteIndex = (autocompleteIndex + 1) % count
        }
        return true
    }
}

// MARK: - Preference key

/// Textfield bounds anchor used to position the autocomplete dropdown below it
struct SearchBarTextFieldBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}
