import Foundation

/// Periodic GC: runs immediately on `start()` then hourly. Three passes per run:
/// age purge, quota purge, orphan-blob cleanup.
///
/// Invariant: pinned clips are never deleted — both purges filter them out in SQL.
@MainActor
final class RetentionJob {

    private let repository: ClipboardRepository
    private let preferences: Preferences

    private var timer: Timer?
    private let tickInterval: TimeInterval = 3600

    var onClipsDeleted: (() -> Void)?

    init(repository: ClipboardRepository, preferences: Preferences) {
        self.repository = repository
        self.preferences = preferences
    }

    func start() {
        guard timer == nil else { return }

        // Run on launch so a stale history gets purged immediately, not after 1h.
        scheduleRun()

        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRun()
            }
        }
    }

    private func scheduleRun() {
        Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Run

    private func run() async {
        var deletedSomething = false

        // Age purge
        if let maxAge = preferences.retentionPolicy.maxAge {
            let cutoff = Date().addingTimeInterval(-maxAge)
            do {
                let staleIDs = try await repository.clipsOlderThan(cutoff)
                if !staleIDs.isEmpty {
                    #if DEBUG
                    print("RetentionJob: purging \(staleIDs.count) clips older than \(cutoff)")
                    #endif
                    try await repository.deleteMany(clipIDs: staleIDs)
                    deletedSomething = true
                }
            } catch {
                #if DEBUG
                print("RetentionJob age purge error:", error)
                #endif
            }
        }

        // Quota purge
        do {
            let totalSize = try await repository.totalStorageSize()
            let quota = preferences.maxCacheSizeBytes
            if totalSize > quota {
                let excess = totalSize - quota
                let candidates = try await repository.oldestUnpinnedClips()

                var freed: Int64 = 0
                var toDelete: [UUID] = []
                for clip in candidates {
                    toDelete.append(clip.id)
                    freed += Int64(clip.totalBytes)
                    if freed >= excess { break }
                }

                if !toDelete.isEmpty {
                    #if DEBUG
                    print("RetentionJob: purging \(toDelete.count) clips to free \(freed) bytes (over quota by \(excess))")
                    #endif
                    try await repository.deleteMany(clipIDs: toDelete)
                    deletedSomething = true
                }
                // If remaining clips are all pinned we stay over quota — pinning wins.
            }
        } catch {
            #if DEBUG
            print("RetentionJob quota purge error:", error)
            #endif
        }

        // Orphan blob cleanup runs regardless of the purges above.
        do {
            try await repository.deleteOrphanBlobs()
        } catch {
            #if DEBUG
            print("RetentionJob blob cleanup error:", error)
            #endif
        }

        if deletedSomething {
            onClipsDeleted?()
        }
    }
}
