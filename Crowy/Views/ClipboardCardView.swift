import SwiftUI

struct ClipboardCardView: View {
    let clip: Clip
    let isSelected: Bool
    let index: Int

    @Environment(AppIconProvider.self) private var iconProvider
    @Environment(LinkPreviewProvider.self) private var linkPreviewProvider

    // MARK: - Layout tokens
    private let cardSize: CGFloat = 232
    private let cornerRadius: CGFloat = Theme.Radius.l
    private let headerHeight: CGFloat = 48
    private let appIconSize: CGFloat = 62+2*6 // 6 is icon padding
    private let appIconBleed: CGFloat = 7+6 // 6 is icon padding
    private let selectionStroke: CGFloat = 4
    private let hPadding: CGFloat = 14
    private let footerBottomPadding: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            headerView
                .frame(height: headerHeight, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(iconProvider.headerColor(forBundleID: clip.sourceAppBundleID))

            contentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.black)
        }
        .frame(width: cardSize, height: cardSize)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Selection stroke drawn outside the clipped card via negative padding; the inter-card gap absorbs the overflow
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius + selectionStroke, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.Palette.selection : Color.clear,
                    lineWidth: selectionStroke
                )
                .padding(-selectionStroke)
        )
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(typeLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(relativeTimestamp)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.leading, hPadding)
            .padding(.top, 6)

            Spacer(minLength: 8)

            // Negative offset bleeds the icon past the header; contentBody's opaque background hides the overflow
            sourceAppBadge
                .offset(x: appIconBleed, y: (-appIconBleed))
        }
    }

    private var typeLabel: String {
        switch clip.primaryKind {
        case .link: return "Link"
        case .text: return "Text"
        case .unknown: return "Text"
        case .color: return "Color"
        case .image: return "Image"
        case .file: return "File"
        }
    }

    private var relativeTimestamp: String {
        let now = Date()
        if abs(clip.createdAt.timeIntervalSince(now)) < 5 {
            return String(localized: "now")
        }
        return Self.relativeFormatter.localizedString(for: clip.createdAt, relativeTo: now)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    // MARK: - App icon

    @ViewBuilder
    private var sourceAppBadge: some View {
        if let icon = iconProvider.icon(forBundleID: clip.sourceAppBundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: appIconSize, height: appIconSize)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentBody: some View {
        switch clip.primaryKind {
        case .unknown: paddedTextBody(clip.previewText, mono: false)
        case .link: linkBody
        case .text: textBody
        case .color: colorBody
        case .image: imageBody
        case .file: fileBody
        }
    }

    private func paddedTextBody(_ text: String, mono: Bool) -> some View {
        Text(text)
            .font(.system(size: mono ? 10 : 12, design: mono ? .monospaced : .default))
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, hPadding)
            .padding(.top, 6)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.78),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var textBody: some View {
        ZStack(alignment: .bottom) {
            Text(clip.previewText)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, hPadding)
                .padding(.top, 6)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.75),
                            .init(color: .clear, location: 0.95),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            HStack(spacing: 0) {
                Text("\(clip.previewText.count) characters")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, hPadding)
            .padding(.bottom, footerBottomPadding)
        }
    }

    private var linkBody: some View {
        let preview = linkPreviewProvider.preview(for: clip.previewText)
        return VStack(spacing: 0) {
            // Greedy Color.black acts as a fixed container; aspectRatio(.fill) on Image would otherwise inflate the card
            Color.black
                .overlay {
                    if let image = preview?.image {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(preview?.title?.isEmpty == false ? preview!.title! : linkFallbackTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(displayURL)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, hPadding)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.04))
        }
        .onAppear {
            linkPreviewProvider.ensureFetched(for: clip.previewText)
        }
    }

    private var linkFallbackTitle: String {
        URL(string: clip.previewText)?.host ?? clip.previewText
    }

    private var displayURL: String {
        guard let url = URL(string: clip.previewText) else { return clip.previewText }
        let host = url.host ?? ""
        return host + url.path
    }

    private var colorBody: some View {
        ZStack {
            (colorFromHex(clip.previewText) ?? .gray)
            Text(clip.previewText.uppercased())
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var imageBody: some View {
        ZStack {
            CheckerboardPattern()
            if let data = clip.thumbnailData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.7))
            Text(clip.previewText)
                .font(.system(size: 12))
                .lineLimit(4)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, hPadding)
        .padding(.top, 6)
    }

    private func colorFromHex(_ hex: String) -> Color? {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let value = UInt32(clean, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}

private struct CheckerboardPattern: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 8
            let cols = Int(ceil(size.width / tile)) + 1
            let rows = Int(ceil(size.height / tile)) + 1
            let dark = Color(white: 0.08)
            let light = Color(white: 0.12)
            for row in 0..<rows {
                for col in 0..<cols {
                    let isDark = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * tile,
                        y: CGFloat(row) * tile,
                        width: tile,
                        height: tile
                    )
                    context.fill(Path(rect), with: .color(isDark ? dark : light))
                }
            }
        }
    }
}
