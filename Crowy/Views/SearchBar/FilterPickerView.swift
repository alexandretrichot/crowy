import SwiftUI

struct FilterPickerView: View {
    let alreadyPinned: [ClipFilter]
    let loadApps: () async -> [SourceAppInfo]
    let onSelect: (ClipFilter) -> Void

    @Environment(AppIconProvider.self) private var iconProvider
    @State private var apps: [SourceAppInfo] = []

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("Type") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Clip.Kind.allCases, id: \.self) { kind in
                            pillButton(
                                label: kind.label,
                                isPinned: alreadyPinned.contains(.kind(kind))
                            ) {
                                Image(systemName: kind.sfSymbol)
                                    .foregroundStyle(Theme.Foreground.secondary)
                            } action: {
                                onSelect(.kind(kind))
                            }
                        }
                    }
                }

                if !apps.isEmpty {
                    sectionDivider
                    section("App") {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(apps.prefix(9), id: \.bundleID) { app in
                                let filter = ClipFilter.app(
                                    bundleID: app.bundleID,
                                    displayName: app.displayName
                                )
                                pillButton(
                                    label: app.displayName,
                                    isPinned: alreadyPinned.contains(filter)
                                ) {
                                    if let icon = iconProvider.icon(forBundleID: app.bundleID) {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                    } else {
                                        Image(systemName: "app")
                                            .foregroundStyle(Theme.Foreground.secondary)
                                    }
                                } action: {
                                    onSelect(filter)
                                }
                            }
                        }
                    }
                }

                sectionDivider
                section("Date") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            pillButton(
                                label: range.label,
                                isPinned: alreadyPinned.contains(.time(range))
                            ) {
                                Image(systemName: range.sfSymbol)
                                    .foregroundStyle(Theme.Foreground.secondary)
                            } action: {
                                onSelect(.time(range))
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
        .frame(width: 520, height: 380)
        .task {
            apps = await loadApps()
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Theme.Divider.subtle)
            .frame(height: 1)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.Foreground.muted)
                .textCase(.uppercase)
                .tracking(0.8)
            content()
        }
    }

    @ViewBuilder
    private func pillButton<Icon: View>(
        label: String,
        isPinned: Bool,
        @ViewBuilder icon: @escaping () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        PillPickerButton(label: label, isPinned: isPinned, icon: icon, action: action)
    }
}

// MARK: - Pill button (with hover)

private struct PillPickerButton<Icon: View>: View {
    let label: String
    let isPinned: Bool
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                icon()
                    .frame(width: 16, height: 16)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Foreground.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(fillOpacity))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered && !isPinned ? 0.18 : 0.08), lineWidth: 1)
            )
            .opacity(isPinned ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isPinned)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var fillOpacity: Double {
        if isPinned { return 0.20 }
        return isHovered ? 0.14 : 0.07
    }
}
