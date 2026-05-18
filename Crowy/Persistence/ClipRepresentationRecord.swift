import Foundation
import GRDB

/// Persistence DTO for `ClipRepresentation`. Carries storage details (inline vs external)
/// that the domain ignores; the inline/external decision belongs to the repository.
struct ClipRepresentationRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "representation"

    var id: Int64?
    var clipID: UUID
    var uti: String
    var storageMode: StorageMode
    var inlineData: Data?
    var externalPath: String?
    var byteSize: Int

    enum StorageMode: String, Codable {
        case inline
        case external
    }

    // GRDB sets the auto-incremented rowid after insert.
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Factories

    /// Small representation: bytes go directly in the BLOB column.
    static func makeInline(domain: ClipRepresentation) -> ClipRepresentationRecord {
        ClipRepresentationRecord(
            id: nil,
            clipID: domain.clipID,
            uti: domain.uti,
            storageMode: .inline,
            inlineData: domain.data,
            externalPath: nil,
            byteSize: domain.byteSize
        )
    }

    /// Large representation: bytes already written to disk; we only keep the path.
    static func makeExternal(domain: ClipRepresentation, externalPath: String) -> ClipRepresentationRecord {
        ClipRepresentationRecord(
            id: nil,
            clipID: domain.clipID,
            uti: domain.uti,
            storageMode: .external,
            inlineData: nil,
            externalPath: externalPath,
            byteSize: domain.byteSize
        )
    }

    // MARK: - Domain mapping (read)

    /// Inverse mapping parameterized by data already hydrated (from BLOB column or disk).
    func domain(hydratedData: Data) -> ClipRepresentation {
        ClipRepresentation(clipID: clipID, uti: uti, data: hydratedData)
    }
}

extension ClipRepresentationRecord {
    enum Columns {
        nonisolated static let id = Column("id")
        nonisolated static let clipID = Column("clipID")
        nonisolated static let uti = Column("uti")
        nonisolated static let storageMode = Column("storageMode")
        nonisolated static let inlineData = Column("inlineData")
        nonisolated static let externalPath = Column("externalPath")
        nonisolated static let byteSize = Column("byteSize")
    }
}
