import Foundation
import GRDB

enum RepositoryError: Error {
    case missingBlobPath
}

/// Source-app summary used by the filter picker.
struct SourceAppInfo: Equatable, Hashable {
    let bundleID: String
    let name: String?
    let count: Int

    var displayName: String { name ?? bundleID }
}

/// Domain-typed API; the only layer that decides inline-DB vs on-disk storage.
final class ClipboardRepository {

    /// Cutoff above which a representation goes to disk instead of an SQLite BLOB.
    /// 64 KB is the empirical sweet spot where SQLite BLOB perf stays good.
    static let inlineThreshold: Int = 64 * 1024

    private let db: Database
    private let blobStore: BlobStore

    init(database: Database, blobStore: BlobStore) {
        self.db = database
        self.blobStore = blobStore
    }

    // MARK: - Write

    func insert(_ clip: Clip, representations: [ClipRepresentation]) async throws {
        let clipRecord = ClipRecord(domain: clip)

        // Write large blobs to disk BEFORE opening the DB transaction. If the DB write
        // later fails, the orphaned blobs are cleaned by the GC; the opposite ordering
        // would leave DB rows pointing at non-existent files, which breaks reads.
        let repRecords: [ClipRepresentationRecord] = try representations.map { rep in
            if rep.byteSize >= Self.inlineThreshold {
                let stored = try blobStore.store(rep.data)
                return .makeExternal(domain: rep, externalPath: stored.relativePath)
            } else {
                return .makeInline(domain: rep)
            }
        }

        // Single transaction so a failure rolls back the whole insert.
        try await db.dbQueue.write { db in
            try clipRecord.insert(db)
            for var rec in repRecords {
                rec.clipID = clip.id
                try rec.insert(db)
            }
        }
    }

    func togglePin(clipID: UUID) async throws {
        try await db.dbQueue.write { db in
            guard var record = try ClipRecord.fetchOne(db, key: clipID) else { return }
            record.isPinned.toggle()
            try record.update(db)
        }
    }

    /// Deletes a clip and cleans up external blobs no longer referenced by any other clip
    /// (two clips can share the same PNG via dedup).
    func delete(clipID: UUID) async throws {
        // In one transaction: snapshot external paths, delete the clip, return orphans.
        let orphanedPaths = try await db.dbQueue.write { db -> [String] in
            let paths = try ClipRepresentationRecord
                .filter(ClipRepresentationRecord.Columns.clipID == clipID)
                .filter(ClipRepresentationRecord.Columns.externalPath != nil)
                .fetchAll(db)
                .compactMap(\.externalPath)

            try ClipRecord.deleteOne(db, key: clipID)
            // representations are removed via cascade.

            return try paths.filter { path in
                let stillUsed = try ClipRepresentationRecord
                    .filter(ClipRepresentationRecord.Columns.externalPath == path)
                    .fetchCount(db) > 0
                return !stillUsed
            }
        }

        // Delete files OUTSIDE the DB transaction. Disk I/O inside a SQLite transaction
        // blocks other writers and risks journal corruption on FS crash. `try?` is fine —
        // if it fails the GC will get it later.
        for path in orphanedPaths {
            try? blobStore.delete(at: path)
        }
    }

    // MARK: - Read

    func clipWithHash(_ hash: String) async throws -> Clip? {
        try await db.dbQueue.read { db in
            try ClipRecord
                .filter(ClipRecord.Columns.contentHash == hash)
                .fetchOne(db)?
                .domain
        }
    }

    /// Distinct source apps with at least one clip, ordered by frequency desc.
    func distinctSourceApps() async throws -> [SourceAppInfo] {
        try await db.dbQueue.read { db in
            try Row
                .fetchAll(
                    db,
                    sql: """
                        SELECT sourceAppBundleID, MAX(sourceAppName) as appName, COUNT(*) as cnt
                        FROM clip
                        WHERE sourceAppBundleID IS NOT NULL
                        GROUP BY sourceAppBundleID
                        ORDER BY cnt DESC
                        """
                )
                .compactMap { row -> SourceAppInfo? in
                    guard let bundleID = row["sourceAppBundleID"] as String? else { return nil }
                    return SourceAppInfo(
                        bundleID: bundleID,
                        name: row["appName"] as String?,
                        count: row["cnt"] as Int? ?? 0
                    )
                }
        }
    }

    /// Unified query. Combines filters as OR within a type (kind:image OR kind:text)
    /// and AND across types (app:Notes AND time:today AND text:"foo"). Adding more types
    /// narrows the result; adding values to a type widens it.
    func clips(matching filters: [ClipFilter], limit: Int = 200) async throws -> [Clip] {
        var kindValues: [String] = []
        var appValues: [String] = []
        var timeRanges: [(start: Date, end: Date?)] = []
        var textPattern: FTS5Pattern?

        for filter in filters {
            switch filter {
            case .kind(let k):
                kindValues.append(k.rawValue)
            case .app(let id, _):
                appValues.append(id)
            case .time(let r):
                timeRanges.append((r.startDate, r.endDate))
            case .text(let q):
                // Only one .text is ever active (it comes from the textInput).
                if let pattern = FTS5Pattern(matchingAllPrefixesIn: q) {
                    textPattern = pattern
                }
            }
        }

        var fromClause = "FROM clip"
        var whereClauses: [String] = []
        var args: [any DatabaseValueConvertible] = []

        if let textPattern {
            fromClause += " JOIN clip_fts ON clip.rowid = clip_fts.rowid"
            whereClauses.append("clip_fts MATCH ?")
            args.append(textPattern)
        }

        if !kindValues.isEmpty {
            let placeholders = Array(repeating: "?", count: kindValues.count).joined(separator: ",")
            whereClauses.append("primaryKind IN (\(placeholders))")
            args.append(contentsOf: kindValues)
        }

        if !appValues.isEmpty {
            let placeholders = Array(repeating: "?", count: appValues.count).joined(separator: ",")
            whereClauses.append("sourceAppBundleID IN (\(placeholders))")
            args.append(contentsOf: appValues)
        }

        if !timeRanges.isEmpty {
            let parts = timeRanges.map { range in
                range.end != nil
                    ? "(createdAt >= ? AND createdAt < ?)"
                    : "(createdAt >= ?)"
            }
            whereClauses.append("(" + parts.joined(separator: " OR ") + ")")
            for range in timeRanges {
                args.append(range.start)
                if let end = range.end {
                    args.append(end)
                }
            }
        }

        var sqlBuilder = "SELECT clip.* \(fromClause)"
        if !whereClauses.isEmpty {
            sqlBuilder += " WHERE " + whereClauses.joined(separator: " AND ")
        }
        sqlBuilder += " ORDER BY clip.createdAt DESC LIMIT ?"
        args.append(limit)

        // Capture into a `let` for the @Sendable closure of dbQueue.read.
        let sql = sqlBuilder
        let statementArgs = StatementArguments(args) ?? StatementArguments()

        return try await db.dbQueue.read { db in
            try ClipRecord
                .fetchAll(db, sql: sql, arguments: statementArgs)
                .map(\.domain)
        }
    }

    /// Hydrates bytes (inline column or on-disk blob) before mapping to domain;
    /// pays one I/O per external rep.
    func representations(of clipID: UUID) async throws -> [ClipRepresentation] {
        let records = try await db.dbQueue.read { db in
            try ClipRepresentationRecord
                .filter(ClipRepresentationRecord.Columns.clipID == clipID)
                .fetchAll(db)
        }

        return try records.map { record in
            let data: Data
            switch record.storageMode {
            case .inline:
                data = record.inlineData ?? Data()
            case .external:
                guard let path = record.externalPath else {
                    throw RepositoryError.missingBlobPath
                }
                data = try blobStore.read(at: path)
            }
            return record.domain(hydratedData: data)
        }
    }

    // MARK: - Garbage collection

    /// Non-pinned clip IDs created before `cutoff`. Pinning takes a clip out of all GC.
    func clipsOlderThan(_ cutoff: Date) async throws -> [UUID] {
        try await db.dbQueue.read { db in
            try ClipRecord
                .filter(ClipRecord.Columns.isPinned == false)
                .filter(ClipRecord.Columns.createdAt < cutoff)
                .fetchAll(db)
                .map(\.id)
        }
    }

    /// Sum of `totalBytes` across all clips (pinned or not); compared against the quota.
    func totalStorageSize() async throws -> Int64 {
        try await db.dbQueue.read { db in
            try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(totalBytes), 0) FROM clip"
            ) ?? 0
        }
    }

    /// Non-pinned clips oldest-first; quota purge removes them FIFO until back under the cap.
    func oldestUnpinnedClips() async throws -> [Clip] {
        try await db.dbQueue.read { db in
            try ClipRecord
                .filter(ClipRecord.Columns.isPinned == false)
                .order(ClipRecord.Columns.createdAt)
                .fetchAll(db)
                .map(\.domain)
        }
    }

    /// Batch delete in one transaction plus orphan-blob cleanup; far faster than looping
    /// `delete(clipID:)` (one transaction instead of N).
    func deleteMany(clipIDs: [UUID]) async throws {
        guard !clipIDs.isEmpty else { return }

        let orphanedPaths = try await db.dbQueue.write { db -> [String] in
            let paths = try ClipRepresentationRecord
                .filter(clipIDs.contains(ClipRepresentationRecord.Columns.clipID))
                .filter(ClipRepresentationRecord.Columns.externalPath != nil)
                .fetchAll(db)
                .compactMap(\.externalPath)

            _ = try ClipRecord
                .filter(clipIDs.contains(ClipRecord.Columns.id))
                .deleteAll(db)

            return try paths.filter { path in
                try ClipRepresentationRecord
                    .filter(ClipRepresentationRecord.Columns.externalPath == path)
                    .fetchCount(db) == 0
            }
        }

        for path in orphanedPaths {
            try? blobStore.delete(at: path)
        }
    }

    /// Safety net: removes blob files not referenced by any rep (covers crashes between
    /// `blobStore.store` and the DB insert — by design we write the blob first).
    func deleteOrphanBlobs() async throws {
        let referencedPaths: Set<String> = try await db.dbQueue.read { db in
            let paths = try ClipRepresentationRecord
                .filter(ClipRepresentationRecord.Columns.externalPath != nil)
                .fetchAll(db)
                .compactMap(\.externalPath)
            return Set(paths)
        }

        let diskFiles = try blobStore.listAllRelativePaths()

        for path in diskFiles where !referencedPaths.contains(path) {
            try? blobStore.delete(at: path)
        }
    }
}
