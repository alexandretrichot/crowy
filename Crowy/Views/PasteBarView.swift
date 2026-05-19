import AppKit
import SwiftUI

/// Root of the focus hierarchy: owns SwiftUI focus state and tracks which child (if any) has taken focus.
/// Leaf-level keys (card nav, paste, close) only fire when `isLeaf` is true.
struct PasteBarView: View {

    // MARK: - Dependencies

    @Bindable var store: ClipboardStore

    /// Source of truth for the user-configured global hotkey, shown in the empty state.
    let preferences: Preferences

    /// Hides the paste panel. Injected so this view doesn't need to know about NSPanel.
    let onClose: () -> Void

    /// Registers (or clears, when passed `nil`) the panel-level Backspace handler.
    /// SwiftUI's `.onKeyPress(.delete)` is unreliable for Backspace; the panel routes it.
    let registerDeleteHandler: ((() -> Void)?) -> Void

    // MARK: - Environment

    /// Captured here so AppKit code (`AppWindowBridge.openSettings`) can open
    /// the SwiftUI `Window` scene — there's no AppKit API to open a scene by ID,
    /// you have to go through this environment value.
    @Environment(\.openWindow) private var openWindow

    // MARK: - Focus hierarchy

    @FocusState private var rootFocused: Bool

    private enum PanelChild: Hashable {
        case searchBar
    }

    @State private var activeChild: PanelChild?

    private var isLeaf: Bool { rootFocused && activeChild == nil }

    // MARK: - Session state

    @State private var tokens: [SearchBarToken] = []
    @State private var selectedID: Clip.ID?
    @State private var filteredClips: [Clip] = []
    @State private var availableApps: [SourceAppInfo] = []

    // MARK: - Layout

    private static let searchBarWidth: CGFloat = 400

    // MARK: - Derived

    private var textInput: String {
        tokens.freeText.trimmingCharacters(in: .whitespaces)
    }

    private var pinnedFilters: [ClipFilter] {
        tokens.filters
    }

    private var allFilters: [ClipFilter] {
        var result = pinnedFilters
        if !textInput.isEmpty { result.append(.text(textInput)) }
        return result
    }

    private var clips: [Clip] {
        allFilters.isEmpty ? store.clips : filteredClips
    }

    private var autocompleteSuggestions: [ClipFilter] {
        matchingFilters(
            query: textInput,
            availableApps: availableApps,
            alreadyPinned: pinnedFilters
        )
    }

    private var emptyStateKind: EmptyStateView.Kind? {
        guard clips.isEmpty else { return nil }
        return allFilters.isEmpty ? .noHistory(hotkey: preferences.hotkey) : .noMatches
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Spacer(minLength: 0)
                    searchBar.frame(width: Self.searchBarWidth)
                    Spacer(minLength: 0)
                }
                HStack {
                    Spacer(minLength: 0)
                    settingsButton
                }
                .padding(.trailing, 14)
            }
            .padding(.top, 14)
            .padding(.bottom, 8)
            // Keep the autocomplete dropdown above the cards rendered after it in the VStack
            .zIndex(1)

            if let kind = emptyStateKind {
                EmptyStateView(kind: kind)
                    .transition(.opacity)
            } else {
                CardsScrollView(
                    clips: clips,
                    selectedID: $selectedID,
                    onPaste: { clip in Task { await store.paste(clip) } }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: emptyStateKind)
        // alignment: .top pins the searchBar; otherwise height differences between EmptyState/Cards shift it
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .glassEffectTransition(.identity)
        .padding(.horizontal, PastePanel.sideMargin)
        .padding(.bottom, PastePanel.bottomMargin)
        .transaction { $0.disablesAnimations = true }
        .focusable()
        .focused($rootFocused)
        .focusEffectDisabled()
        .onAppear {
            activeChild = nil
            rootFocused = true
            ensureSelectionValid()
            registerDeleteHandler { deleteSelected() }

            // Re-bind on every appearance — `openWindow` is captured at this
            // point, so AppKit callers (Cmd+, in PastePanel, the gear button)
            // can route through it. Idempotent.
            //
            // `NSApp.activate` (without flipping activation policy to `.regular`)
            // makes the app frontmost so the SwiftUI `Window` scene surfaces in
            // front. Activation policy stays `.accessory` → no Dock icon.
            AppWindowBridge.shared.openSettings = {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: WindowID.settings)
            }
        }
        .onDisappear {
            registerDeleteHandler(nil)
        }
        .onChange(of: clips) { _, _ in ensureSelectionValid() }
        .onChange(of: store.clips.first?.id) { _, newTopID in
            // New clip ingested: auto-select if visible in the filtered list
            guard let topID = newTopID,
                  clips.contains(where: { $0.id == topID }) else { return }
            selectedID = topID
        }
        .task(id: allFilters) { await runQuery() }
        .task { await loadAvailableApps() }
        .modifier(LeafKeyHandlers(view: self))
    }

    // MARK: - Settings entry

    private var settingsButton: some View {
        IconButton(
            systemName: "gearshape",
            size: 14,
            weight: .semibold,
            tint: 0.55
        ) {
            // Goes through the bridge so the .accessory→.regular flip happens
            // before openWindow — otherwise the window opens behind the paste bar.
            AppWindowBridge.shared.openSettings()
        }
    }

    // MARK: - Search bar composition

    private var searchBar: some View {
        SearchBarView(
            isActive: searchBarActiveBinding,
            tokens: $tokens,
            placeholder: "Search",
            pinnedFilters: pinnedFilters,
            autocompleteSuggestions: autocompleteSuggestions,
            onFilterPicked: addFilter,
            onClear: {
                clearFilters()
                returnFocusToPanel()
            },
            onEnterIdle: returnFocusToPanel,
            onEscapeIdle: {
                if !tokens.isEmpty {
                    clearFilters()
                } else {
                    returnFocusToPanel()
                }
            },
            loadApps: {
                await loadAvailableApps()
                return availableApps
            }
        )
    }

    // MARK: - Coordinated bindings

    private var searchBarActiveBinding: Binding<Bool> {
        Binding(
            get: { activeChild == .searchBar },
            set: { active in activeChild = active ? .searchBar : nil }
        )
    }

    // MARK: - Focus transitions

    private func returnFocusToPanel() {
        activeChild = nil
        rootFocused = true
    }

    // MARK: - Filter actions

    private func addFilter(_ filter: ClipFilter) {
        if case .text = filter { return }
        var newTokens = tokens.filter {
            if case .text = $0 { return false }
            return true
        }
        newTokens.append(.filter(filter))
        tokens = newTokens
    }

    private func clearFilters() {
        tokens = []
    }

    private func appendText(_ chars: String) {
        if case .text(let s) = tokens.last {
            tokens[tokens.count - 1] = .text(s + chars)
        } else {
            tokens.append(.text(chars))
        }
    }

    // MARK: - Selection

    fileprivate func ensureSelectionValid() {
        if let id = selectedID, clips.contains(where: { $0.id == id }) { return }
        selectedID = clips.first?.id
    }

    fileprivate func selectNext() {
        guard !clips.isEmpty else { return }
        guard let current = selectedID,
              let i = clips.firstIndex(where: { $0.id == current }) else {
            selectedID = clips.first?.id
            return
        }
        selectedID = clips[min(i + 1, clips.count - 1)].id
    }

    fileprivate func selectPrev() {
        guard !clips.isEmpty else { return }
        guard let current = selectedID,
              let i = clips.firstIndex(where: { $0.id == current }) else {
            selectedID = clips.first?.id
            return
        }
        selectedID = clips[max(i - 1, 0)].id
    }

    // MARK: - Clip actions

    fileprivate func pasteSelected() {
        guard let id = selectedID,
              let clip = clips.first(where: { $0.id == id }) else { return }
        Task { await store.paste(clip) }
    }

    fileprivate func deleteSelected() {
        guard let id = selectedID,
              let i = clips.firstIndex(where: { $0.id == id }) else { return }
        let nextID: Clip.ID? = {
            if i + 1 < clips.count { return clips[i + 1].id }
            if i - 1 >= 0          { return clips[i - 1].id }
            return nil
        }()
        Task {
            await store.delete(clipID: id)
            selectedID = nextID
        }
    }

    fileprivate func closePanel() {
        onClose()
    }

    // MARK: - Async loading

    private func runQuery() async {
        guard !allFilters.isEmpty else {
            filteredClips = []
            return
        }
        do {
            let results = try await store.clips(matching: allFilters)
            try Task.checkCancellation()
            filteredClips = results
        } catch is CancellationError {
            return
        } catch {
            #if DEBUG
            print("Filter query error:", error)
            #endif
            filteredClips = []
        }
    }

    private func loadAvailableApps() async {
        do {
            availableApps = try await store.distinctSourceApps()
        } catch {
            #if DEBUG
            print("loadAvailableApps error:", error)
            #endif
        }
    }

    // MARK: - Keyboard routing (leaf-level keys)

    fileprivate var isLeafForKeyHandlers: Bool { isLeaf }

    fileprivate func handleTypeToSearch(_ keyPress: KeyPress) -> KeyPress.Result {
        let shortcutMods: EventModifiers = [.command, .control, .option]
        guard keyPress.modifiers.intersection(shortcutMods).isEmpty else { return .ignored }
        guard let first = keyPress.characters.first,
              first.isLetter || first.isNumber || first.isPunctuation
        else { return .ignored }
        appendText(keyPress.characters)
        activeChild = .searchBar
        return .handled
    }

    fileprivate func handleCmdV(_ keyPress: KeyPress) -> Bool {
        let cmdOnly = keyPress.modifiers
            .intersection([.command, .control, .option]) == .command
        guard cmdOnly, keyPress.characters.lowercased() == "v" else { return false }
        pasteSelected()
        return true
    }
}

// MARK: - Filter matching

private func matchingFilters(
    query: String,
    availableApps: [SourceAppInfo],
    alreadyPinned: [ClipFilter]
) -> [ClipFilter] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return [] }

    var matches: [ClipFilter] = []

    for kind in Clip.Kind.allCases where kind.label.lowercased().contains(q) {
        let filter = ClipFilter.kind(kind)
        if !alreadyPinned.contains(filter) { matches.append(filter) }
    }

    for range in TimeRange.allCases where range.label.lowercased().contains(q) {
        let filter = ClipFilter.time(range)
        if !alreadyPinned.contains(filter) { matches.append(filter) }
    }

    for app in availableApps {
        guard app.displayName.lowercased().contains(q) else { continue }
        let filter = ClipFilter.app(bundleID: app.bundleID, displayName: app.displayName)
        if !alreadyPinned.contains(filter) { matches.append(filter) }
    }

    return Array(matches.prefix(8))
}

// MARK: - Leaf key handlers

/// Routes keys only when the panel is the focus-hierarchy leaf; child views consume natively when active.
private struct LeafKeyHandlers: ViewModifier {
    let view: PasteBarView

    private func ifLeaf(_ action: () -> Void) -> KeyPress.Result {
        guard view.isLeafForKeyHandlers else { return .ignored }
        action()
        return .handled
    }

    func body(content: Content) -> some View {
        content
            .onKeyPress(.leftArrow)  { ifLeaf { view.selectPrev() } }
            .onKeyPress(.rightArrow) { ifLeaf { view.selectNext() } }
            .onKeyPress(.return)     { ifLeaf { view.pasteSelected() } }
            .onKeyPress(.escape)     { ifLeaf { view.closePanel() } }
            .onKeyPress { keyPress in
                guard view.isLeafForKeyHandlers else { return .ignored }
                if view.handleCmdV(keyPress) { return .handled }
                return view.handleTypeToSearch(keyPress)
            }
    }
}
