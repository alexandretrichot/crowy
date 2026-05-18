import Foundation

/// Domain entity for a clipboard item. Persistence-agnostic; mapping lives in `ClipRecord`.
struct Clip: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date

    var primaryKind: Kind

    /// Display text shown in the card and indexed for search. For images/files, a descriptor like "image, 2.3 MB".
    var previewText: String

    /// SHA-256 of the canonical representation; used for dedup.
    var contentHash: String

    var sourceAppBundleID: String?
    var sourceAppName: String?

    var totalBytes: Int

    var isPinned: Bool

    /// 200x200 JPEG thumbnail stored inline (~10 KB) for synchronous view access.
    var thumbnailData: Data?

    enum Kind: String, Codable, CaseIterable {
        case unknown, image, color, file, link, text

        // Tolerant decode: legacy DB values "url" -> .link, "code" -> .text.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            switch raw {
            case "url":  self = .link
            case "code": self = .text
            default:
                guard let kind = Kind(rawValue: raw) else {
                    throw DecodingError.dataCorruptedError(
                        in: try decoder.singleValueContainer(),
                        debugDescription: "Unknown Clip.Kind: \(raw)"
                    )
                }
                self = kind
            }
        }
    }
}
