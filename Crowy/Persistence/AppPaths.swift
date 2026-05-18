import Foundation

/// Disk paths used by the persistence layer.
enum AppPaths {

    /// `~/Library/Application Support/<bundleID>/`, created if absent.
    static var applicationSupport: URL {
        get throws {
            let fm = FileManager.default
            let base = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            guard let bundleID = Bundle.main.bundleIdentifier else {
                fatalError("Bundle identifier missing — Info.plist is corrupt or app is mis-packaged.")
            }
            let dir = base.appendingPathComponent(bundleID, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)

            // Restrict to the owning user: clipboard history may contain anything
            // the user copied. 0o700 blocks other local accounts from listing or
            // reading the DB and blob files, even without full-disk encryption.
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)

            return dir
        }
    }

    static var database: URL {
        get throws { try applicationSupport.appendingPathComponent("paste.sqlite") }
    }

    static var blobStoreRoot: URL {
        get throws { try applicationSupport.appendingPathComponent("blobs", isDirectory: true) }
    }
}
