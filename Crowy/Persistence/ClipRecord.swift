import Foundation
import GRDB

/// GRDB persistence DTO for `Clip`. The repository maps `Clip <-> ClipRecord` on every
/// read/write so the domain stays GRDB-free and the schema can evolve independently.
struct ClipRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "clip"

    var id: UUID
    var createdAt: Date
    var primaryKind: Clip.Kind
    var previewText: String
    var contentHash: String
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var totalBytes: Int
    var isPinned: Bool
    var thumbnailData: Data?

    // MARK: - Domain mapping

    init(domain: Clip) {
        self.id = domain.id
        self.createdAt = domain.createdAt
        self.primaryKind = domain.primaryKind
        self.previewText = domain.previewText
        self.contentHash = domain.contentHash
        self.sourceAppBundleID = domain.sourceAppBundleID
        self.sourceAppName = domain.sourceAppName
        self.totalBytes = domain.totalBytes
        self.isPinned = domain.isPinned
        self.thumbnailData = domain.thumbnailData
    }

    var domain: Clip {
        Clip(
            id: id,
            createdAt: createdAt,
            primaryKind: primaryKind,
            previewText: previewText,
            contentHash: contentHash,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            totalBytes: totalBytes,
            isPinned: isPinned,
            thumbnailData: thumbnailData
        )
    }
}

extension ClipRecord {
    enum Columns {
        nonisolated static let id = Column("id")
        nonisolated static let createdAt = Column("createdAt")
        nonisolated static let primaryKind = Column("primaryKind")
        nonisolated static let previewText = Column("previewText")
        nonisolated static let contentHash = Column("contentHash")
        nonisolated static let isPinned = Column("isPinned")
    }
}
