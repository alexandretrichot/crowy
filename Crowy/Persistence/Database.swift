import Foundation
import GRDB

/// Database stack. `DatabaseQueue` serializes all access — fine for a single-user
/// desktop app; switch to `DatabasePool` only if parallel reads become a need.
final class Database {

    let dbQueue: DatabaseQueue

    init() throws {
        let url = try AppPaths.database

        var config = Configuration()
        // Required for `ON DELETE CASCADE` on representations.clipID to work at runtime.
        config.foreignKeysEnabled = true

        self.dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        try Self.migrator.migrate(dbQueue)
    }

    // MARK: - Migrations

    /// Migrations are immutable once shipped. To change the schema later, add a new one
    /// (v2, v3, ...); GRDB applies pending migrations in order on each user's local DB.
    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1_initial") { db in
            try db.create(table: "clip") { t in
                t.column("id", .text).primaryKey()
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("primaryKind", .text).notNull()
                t.column("previewText", .text).notNull()
                t.column("contentHash", .text).notNull().indexed()  // indexed for fast dedup
                t.column("sourceAppBundleID", .text)
                t.column("sourceAppName", .text)
                t.column("totalBytes", .integer).notNull()
                t.column("isPinned", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "representation") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("clipID", .text)
                    .notNull()
                    .indexed()
                    .references("clip", column: "id", onDelete: .cascade)
                t.column("uti", .text).notNull()
                t.column("storageMode", .text).notNull()
                t.column("inlineData", .blob)
                t.column("externalPath", .text)
                t.column("byteSize", .integer).notNull()
            }
        }

        // FTS5 on `previewText`. `synchronize(withTable:)` configures external content
        // (`content='clip'`, `content_rowid='rowid'`), installs AFTER INSERT/UPDATE/DELETE
        // triggers that mirror clip changes into clip_fts, and backfills existing rows.
        m.registerMigration("v2_fts5") { db in
            try db.create(virtualTable: "clip_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clip")
                // unicode61 tokenizer: case-insensitive, diacritics removed so "café" matches "cafe".
                t.tokenizer = .unicode61(diacritics: .remove)
                t.column("previewText")
            }
        }

        // Thumbnails stored inline (~10 KB JPEG-q70). Existing rows keep NULL, no backfill.
        m.registerMigration("v3_thumbnail") { db in
            try db.alter(table: "clip") { t in
                t.add(column: "thumbnailData", .blob)
            }
        }

        return m
    }
}
