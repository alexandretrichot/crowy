import SwiftUI

struct OnboardingView: View {
    @Bindable var permissions: PermissionsManager
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            header
            permissionCard
            Spacer(minLength: 0)
            footer
        }
        .padding(32)
        .frame(width: 460, height: 420)
        .onChange(of: permissions.isAccessibilityGranted) { _, granted in
            // Brief delay so the user sees the animated checkmark before dismissing.
            if granted {
                Task {
                    try? await Task.sleep(for: .milliseconds(900))
                    onDismiss()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            Text("Welcome to Crowy")
                .font(.system(size: 22, weight: .semibold))

            Text("To paste from your history with **Enter**, Crowy needs Accessibility.\nWithout it, you can still browse your clips — paste-back won't work.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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
                     : "Required to send ⌘V to other apps.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
        Group {
            if permissions.isAccessibilityGranted {
                Button("Continue") { onDismiss() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Continue without paste-back") { onDismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
