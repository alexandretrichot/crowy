import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Standalone settings window content. Custom flat layout (not `Form.grouped`)
/// so the look matches modern utility-app conventions instead of System Settings.
struct SettingsView: View {

    @Bindable var preferences: Preferences
    let onHotkeyChange: (HotkeyBinding) -> Void
    let onQuit: () -> Void

    @State private var selection: Section = .general

    private enum Section: String, CaseIterable, Identifiable, Hashable {
        case general, shortcuts, history, privacy
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:   return "General"
            case .shortcuts: return "Shortcuts"
            case .history:   return "History"
            case .privacy:   return "Privacy"
            }
        }

        var symbol: String {
            switch self {
            case .general:   return "gearshape"
            case .shortcuts: return "keyboard"
            case .history:   return "clock.arrow.circlepath"
            case .privacy:   return "hand.raised"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(selection.title)
                        .font(.system(size: 22, weight: .semibold))

                    detail
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 820, minHeight: 640)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:   GeneralPane(preferences: preferences, onQuit: onQuit)
        case .shortcuts: ShortcutsPane(preferences: preferences, onHotkeyChange: onHotkeyChange)
        case .history:   HistoryPane(preferences: preferences)
        case .privacy:   PrivacyPane(preferences: preferences)
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable var preferences: Preferences
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup {
                SettingsToggleRow(
                    title: "Launch at login",
                    subtitle: "Crowy starts automatically when you log in.",
                    isOn: launchAtLoginBinding
                )
            }

            SettingsGroup(title: "App") {
                SettingsRow(
                    title: "Quit the app",
                    subtitle: "Reopen from Spotlight or Applications."
                ) {
                    Button("Quit Crowy", role: .destructive) { onQuit() }
                }
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { preferences.launchAtLogin },
            set: { newValue in
                let ok = LaunchAtLoginManager.setEnabled(newValue)
                preferences.launchAtLogin = ok ? newValue : LaunchAtLoginManager.isEnabled
            }
        )
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    @Bindable var preferences: Preferences
    let onHotkeyChange: (HotkeyBinding) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup {
                SettingsRow(
                    title: "Show Crowy",
                    subtitle: "Press this shortcut anywhere to open the paste bar."
                ) {
                    HStack(spacing: 6) {
                        HotkeyRecorderView(binding: hotkeyBinding)
                        Button("Reset") {
                            hotkeyBinding.wrappedValue = .default
                        }
                        .controlSize(.small)
                    }
                }
            }

            Text("Press **Esc** to cancel recording. The shortcut needs at least one modifier (⌘ ⌥ ⌃ ⇧).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
        }
    }

    private var hotkeyBinding: Binding<HotkeyBinding> {
        Binding(
            get: { preferences.hotkey },
            set: { newValue in
                preferences.hotkey = newValue
                onHotkeyChange(newValue)
            }
        )
    }
}

// MARK: - History

private struct HistoryPane: View {
    @Bindable var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "Keep history") {
                SegmentedSliderRow(
                    options: RetentionPolicy.allCases,
                    selection: retentionBinding,
                    label: { $0.label }
                )
            }

            SettingsGroup(title: "Cache size") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Maximum on-disk cache")
                        Spacer()
                        Text(formatBytes(preferences.maxCacheSizeBytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: cacheSizeGBBinding,
                        in: 1...50,
                        step: 1
                    ) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("1 GB").font(.caption2).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("50 GB").font(.caption2).foregroundStyle(.secondary)
                    }

                    Text("Oldest unpinned clips are dropped above this threshold.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var retentionBinding: Binding<RetentionPolicy> {
        Binding(
            get: { preferences.retentionPolicy },
            set: { preferences.retentionPolicy = $0 }
        )
    }

    private var cacheSizeGBBinding: Binding<Double> {
        Binding(
            get: { Double(preferences.maxCacheSizeBytes) / Double(1024 * 1024 * 1024) },
            set: { gb in
                preferences.maxCacheSizeBytes = Int64(gb * 1024 * 1024 * 1024)
            }
        )
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB]
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Privacy

private struct PrivacyPane: View {
    @Bindable var preferences: Preferences

    @State private var entries: [BlacklistEntry] = []

    private struct BlacklistEntry: Identifiable, Equatable {
        let bundleID: String
        let displayName: String
        let icon: NSImage?
        var id: String { bundleID }
    }

    var body: some View {
        SettingsGroup(title: "Excluded apps") {
            VStack(spacing: 0) {
                if entries.isEmpty {
                    Text("No apps excluded.")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 14)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 10) {
                            Group {
                                if let icon = entry.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Image(systemName: "app")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 22, height: 22)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.displayName)
                                Text(entry.bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                preferences.removeFromBlacklist(bundleID: entry.bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.large)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)

                        if index < entries.count - 1 {
                            SettingsRowDivider()
                        }
                    }
                }

                SettingsRowDivider()

                HStack {
                    Button {
                        pickApp()
                    } label: {
                        Label("Add app…", systemImage: "plus")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                .padding(.vertical, 10)
            }

            Text("Copies made in these apps are never saved.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .onAppear(perform: refreshEntries)
        .onChange(of: preferences.blacklistedBundleIDs) { _, _ in refreshEntries() }
    }

    private func refreshEntries() {
        let ids = preferences.blacklistedBundleIDs.sorted()
        entries = ids.map { id in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let displayName: String = {
                if let url {
                    return FileManager.default.displayName(atPath: url.path)
                        .replacingOccurrences(of: ".app", with: "")
                }
                return id
            }()
            let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            return BlacklistEntry(bundleID: id, displayName: displayName, icon: icon)
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to exclude"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            NSSound.beep()
            return
        }
        preferences.addToBlacklist(bundleID: id)
    }
}

// MARK: - Layout primitives

/// Section container: optional title, content stacked vertically. No card chrome —
/// the window's material handles the surface.
private struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            content
        }
    }
}

/// A horizontal row: title (+ optional subtitle) on the left, trailing control on the right.
private struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 8)
    }
}

/// Toggle row — `SettingsRow` specialised for a switch.
private struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

/// 1px subtle horizontal separator used between rows in the same group.
private struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
    }
}

// MARK: - Segmented slider

/// Discrete labelled slider: tick marks under each option, a draggable thumb,
/// labels rendered below. Mirrors the "Day · Week · Month · Forever" pattern
/// from competing clipboard managers' settings.
private struct SegmentedSliderRow<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let count = max(options.count - 1, 1)
                let step = width / CGFloat(count)
                let index = options.firstIndex(of: selection) ?? 0

                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 4)

                    // Ticks
                    HStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.offset) { i, _ in
                            Circle()
                                .fill(Color.primary.opacity(i <= index ? 0.6 : 0.18))
                                .frame(width: 6, height: 6)
                            if i < options.count - 1 { Spacer(minLength: 0) }
                        }
                    }

                    // Thumb
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .frame(width: 18, height: 18)
                        .offset(x: step * CGFloat(index) - 9)
                }
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let raw = value.location.x / step
                            let clamped = min(max(raw.rounded(), 0), CGFloat(count))
                            let newIndex = Int(clamped)
                            if newIndex < options.count {
                                let newOption = options[newIndex]
                                if newOption != selection { selection = newOption }
                            }
                        }
                )
            }
            .frame(height: 22)
            .padding(.horizontal, 9) // inset so the thumb doesn't clip at the ends

            // Labels
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                    Text(label(opt))
                        .font(.system(size: 11))
                        .foregroundStyle(options[i] == selection ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
