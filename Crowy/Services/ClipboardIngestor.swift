import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Filters, classifies, dedups and persists pasteboard snapshots from the monitor.
@MainActor
final class ClipboardIngestor {

    private let repository: ClipboardRepository
    private let filter: PasteboardFilter

    var onClipInserted: (() -> Void)?

    init(repository: ClipboardRepository, filter: PasteboardFilter) {
        self.repository = repository
        self.filter = filter
    }

    func ingest(_ snapshot: ClipboardMonitor.PasteboardSnapshot) {
        switch filter.decide(snapshot) {
        case .reject:
            return
        case .accept:
            Task { @MainActor in
                do {
                    try await persist(snapshot)
                } catch {
                    #if DEBUG
                    print("Ingestor error:", error)
                    #endif
                }
            }
        }
    }

    // MARK: - Pipeline

    private func persist(_ snapshot: ClipboardMonitor.PasteboardSnapshot) async throws {
        let reps = snapshot.representations
        guard let primaryKind = inferKind(from: reps.keys.map { $0 }) else { return }
        let previewText = makePreviewText(reps: reps, kind: primaryKind)
        let hash = computeHash(reps: reps)

        if try await repository.clipWithHash(hash) != nil { return }

        let clipID = UUID()
        let totalBytes = reps.values.reduce(0) { $0 + $1.count }

        // Inline 200×200 JPEG thumbnail so cards don't have to load multi-MB originals.
        let thumbnail = primaryKind == .image ? Self.makeThumbnail(from: reps) : nil

        let clip = Clip(
            id: clipID,
            createdAt: snapshot.capturedAt,
            primaryKind: primaryKind,
            previewText: previewText,
            contentHash: hash,
            sourceAppBundleID: snapshot.sourceAppBundleID,
            sourceAppName: snapshot.sourceAppName,
            totalBytes: totalBytes,
            isPinned: false,
            thumbnailData: thumbnail
        )

        let representations: [ClipRepresentation] = reps.map { uti, data in
            ClipRepresentation(clipID: clipID, uti: uti, data: data)
        }

        try await repository.insert(clip, representations: representations)
        onClipInserted?()
    }

    // MARK: - Type inference

    /// Priority: image > file > url > text. Reflects likely user intent when an
    /// app emits multiple reps (Figma emits PNG + text "Rectangle 4" — pick image).
    private func inferKind(from utis: [String]) -> Clip.Kind? {
        let set = Set(utis)

        let imageUTIs: Set<String> = ["public.png", "public.jpeg", "public.tiff", "public.heic"]
        let fileUTIs: Set<String> = ["public.file-url"]
        let urlUTIs: Set<String> = ["public.url"]
        let textUTIs: Set<String> = ["public.utf8-plain-text", "public.text", "public.plain-text"]

        if !set.isDisjoint(with: imageUTIs) { return .image }
        if !set.isDisjoint(with: fileUTIs) { return .file }
        if !set.isDisjoint(with: urlUTIs) { return .link }
        if !set.isDisjoint(with: textUTIs) { return .text }
        return nil
    }

    // MARK: - Preview text

    /// Card display + search index text. Capped at 500 chars to keep the DB small.
    private func makePreviewText(reps: [String: Data], kind: Clip.Kind) -> String {
        switch kind {
        case .image:
            let bytes = reps.values.reduce(0) { $0 + $1.count }
            return "Image (\(byteFormatter.string(fromByteCount: Int64(bytes))))"
        case .file:
            if let urlData = reps["public.file-url"],
               let str = String(data: urlData, encoding: .utf8) {
                return URL(string: str)?.lastPathComponent ?? str
            }
            return "File"
        default:
            for key in ["public.utf8-plain-text", "public.text", "public.plain-text", "public.url"] {
                if let data = reps[key], let str = String(data: data, encoding: .utf8) {
                    return String(str.prefix(500))
                }
            }
            return ""
        }
    }

    // MARK: - Hash

    /// SHA-256 over UTIs sorted alphabetically + their bytes, so identical
    /// snapshots always hash the same.
    private func computeHash(reps: [String: Data]) -> String {
        var hasher = SHA256()
        for uti in reps.keys.sorted() {
            hasher.update(data: Data(uti.utf8))
            if let data = reps[uti] {
                hasher.update(data: data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    // MARK: - Thumbnail

    /// 200×200 JPEG q70 via ImageIO so we don't materialize a 4000×4000 source in memory.
    private static func makeThumbnail(from reps: [String: Data]) -> Data? {
        // PNG first: macOS screenshots are PNG and that's the most copied image type.
        let preferredUTIs = ["public.png", "public.jpeg", "public.heic", "public.tiff"]
        guard let data = preferredUTIs.compactMap({ reps[$0] }).first else {
            return nil
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 200,
            kCGImageSourceCreateThumbnailWithTransform: true,  // honor EXIF orientation
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
}
