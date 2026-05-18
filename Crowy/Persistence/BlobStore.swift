import CryptoKit
import Foundation

/// Content-addressed store for large blobs (images, PDFs, files).
///
/// Path layout: `blobs/<first 2 hex chars of hash>/<full hash>`. Two free properties:
/// dedup (identical content -> same file, second write is a no-op) and sharding
/// (2-char subdir avoids 100k+ files in a single directory).
struct BlobStore {

    let rootURL: URL

    init(rootURL: URL) throws {
        self.rootURL = rootURL
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    struct StoredBlob {
        let hash: String          // SHA-256 hex
        let relativePath: String  // "ab/abcdef..." relative to rootURL
    }

    /// Idempotent: returns the relative path; skips the write if a file with the same hash already exists.
    func store(_ data: Data) throws -> StoredBlob {
        let hash = Self.sha256(data)
        let relativePath = Self.path(forHash: hash)
        let url = rootURL.appendingPathComponent(relativePath)

        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // .atomic writes to tmp then renames — avoids partial files if the app crashes mid-write.
            try data.write(to: url, options: .atomic)
        }

        return StoredBlob(hash: hash, relativePath: relativePath)
    }

    func read(at relativePath: String) throws -> Data {
        let url = rootURL.appendingPathComponent(relativePath)
        return try Data(contentsOf: url)
    }

    /// Best-effort; does not fail if the file is already gone.
    func delete(at relativePath: String) throws {
        let url = rootURL.appendingPathComponent(relativePath)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    /// Enumerates all blobs on disk as "{prefix2}/{hash}". Used by the GC to find orphans.
    func listAllRelativePaths() throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootURL.path) else { return [] }

        var results: [String] = []
        let subdirs = try fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        for subdir in subdirs {
            let isDir = (try? subdir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let files = try fm.contentsOfDirectory(at: subdir, includingPropertiesForKeys: nil)
            for file in files {
                results.append("\(subdir.lastPathComponent)/\(file.lastPathComponent)")
            }
        }
        return results
    }

    // MARK: - Hash + path

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func path(forHash hash: String) -> String {
        let prefix = String(hash.prefix(2))
        return "\(prefix)/\(hash)"
    }
}
