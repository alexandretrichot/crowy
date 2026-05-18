import SwiftUI

/// Generic icon button with a hover background. Hover tweaks the tint and adds
/// a subtle background circle without changing size, so layout doesn't shift.
struct IconButton: View {
    let systemName: String
    var size: CGFloat = 12
    var weight: Font.Weight = .regular
    var tint: Double = 0.6
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(Color.primary.opacity(isHovered ? min(tint + 0.25, 1.0) : tint))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
