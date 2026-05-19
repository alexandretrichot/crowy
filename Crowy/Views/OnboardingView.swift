import SwiftUI

struct OnboardingView: View {
    @Bindable var permissions: PermissionsManager
    let hotkey: HotkeyBinding
    let onPermissionGranted: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            header
            featureList
            permissionCard
            Spacer(minLength: 0)
            footer
        }
        .padding(28)
        .frame(width: 480, height: 560)
        .onChange(of: permissions.isAccessibilityGranted) { _, granted in
            // System Settings steals focus during the grant flow; pull the
            // onboarding panel back so the user sees the green confirmation
            // and can read what's next instead of hunting for the window.
            if granted { onPermissionGranted() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text("Welcome to Crowy")
                .font(.system(size: 22, weight: .semibold))

            Text("Your clipboard history, one shortcut away.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Feature list

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(
                icon: "eye.slash",
                title: "Stays out of your way",
                detail: "No Dock icon, no menu bar item — Crowy is invisible until you call it."
            )
            featureRow(
                icon: "keyboard",
                title: "Open with \(hotkey.displayString)",
                detail: "Press the shortcut anywhere to browse what you've copied."
            )
            featureRow(
                icon: "return",
                title: "Paste with Enter",
                detail: "Pick a clip and Crowy sends ⌘V to the focused app. Settings live behind the ⚙︎ in the paste bar."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .frame(width: 22, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Permission card

    private var permissionCard: some View {
        HStack(spacing: 12) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility")
                    .font(.system(size: 13, weight: .medium))
                Text(permissions.isAccessibilityGranted
                     ? "Granted — paste-back is ready."
                     : "Lets Crowy send ⌘V to the focused app. Without it, you can still browse but Enter won't paste.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()

            if !permissions.isAccessibilityGranted {
                Button("Grant…") {
                    permissions.requestAccessibility()
                }
                .controlSize(.regular)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        if permissions.isAccessibilityGranted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: permissions.isAccessibilityGranted)
        } else {
            Image(systemName: "lock.circle")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Button(permissions.isAccessibilityGranted ? "Get started" : "Continue without paste-back") {
            onDismiss()
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .tint(permissions.isAccessibilityGranted ? .accentColor : .secondary)
    }
}
