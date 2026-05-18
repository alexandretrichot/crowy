import AppKit

/// Conversions between `[SearchBarToken]` and `NSAttributedString`. Centralises shared text/line metrics so pills and the cursor stay vertically aligned.
enum SearchBarTokenCoder {

    // MARK: - Layout metrics

    /// Shared line height; pills and cursor both use this via paragraph style min/maxLineHeight
    nonisolated static let lineHeight: CGFloat = 22

    /// Text attributes for search-bar runs. Paragraph style pins lineHeight; baselineOffset recentres glyphs (AppKit otherwise sits them too low). Consumed by `PillAttachmentCell.cellBaselineOffset()`.
    nonisolated static var textAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph,
            .baselineOffset: textBaselineOffset,
        ]
    }

    /// Half-leading added to the text baseline so glyphs centre in the forced line; shared with the pill offset calculation
    nonisolated static var textBaselineOffset: CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        let naturalHeight = font.ascender - font.descender
        return (lineHeight - naturalHeight) / 2
    }

    // MARK: - Pasteboard

    /// Custom type for within-app token round-trip; outside our app, other pasteboards fall back to plain text
    static let pasteboardType = NSPasteboard.PasteboardType("fr.alexandretrichot.Crowy.search-tokens")

    // MARK: - Encoding

    static func extract(from attr: NSAttributedString) -> [SearchBarToken] {
        var tokens: [SearchBarToken] = []
        var textBuffer = ""

        attr.enumerateAttribute(.attachment,
                                in: NSRange(location: 0, length: attr.length),
                                options: []) { value, range, _ in
            if let pill = value as? PillTextAttachment {
                if !textBuffer.isEmpty {
                    tokens.append(.text(textBuffer))
                    textBuffer = ""
                }
                tokens.append(.filter(pill.filter))
            } else {
                textBuffer += (attr.string as NSString).substring(with: range)
            }
        }
        if !textBuffer.isEmpty {
            tokens.append(.text(textBuffer))
        }
        return tokens
    }

    static func build(from tokens: [SearchBarToken]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for token in tokens {
            switch token {
            case .text(let s):
                result.append(NSAttributedString(string: s, attributes: textAttributes))
            case .filter(let f):
                let attachment = PillTextAttachment(filter: f)
                result.append(NSAttributedString(attachment: attachment))
            }
        }
        return result
    }

    /// Plain-text fallback for cross-app paste; pills render as their label
    static func renderPlainText(from tokens: [SearchBarToken]) -> String {
        tokens.map {
            switch $0 {
            case .text(let s): return s
            case .filter(let f): return f.pillLabel
            }
        }.joined(separator: " ")
    }
}
