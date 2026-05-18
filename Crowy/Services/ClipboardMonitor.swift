import AppKit

/// Polls the system pasteboard; emits a snapshot of all UTI reps on each change.
@MainActor
final class ClipboardMonitor {

    struct PasteboardSnapshot {
        var representations: [String: Data]
        var sourceAppBundleID: String?
        var sourceAppName: String?
        var capturedAt: Date
    }

    var onNewSnapshot: ((PasteboardSnapshot) -> Void)?

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pollInterval: TimeInterval = 0.4

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount

        timer = Timer.scheduledTimer(
            withTimeInterval: pollInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        guard let snapshot = capture(from: pb) else { return }
        onNewSnapshot?(snapshot)
    }

    /// Takes only the first pasteboard item — multi-item drags are ignored for now.
    private func capture(from pb: NSPasteboard) -> PasteboardSnapshot? {
        guard let item = pb.pasteboardItems?.first else { return nil }

        var reps: [String: Data] = [:]
        for type in item.types {
            // Materializes promised representations (some apps defer big allocations).
            if let data = item.data(forType: type) {
                reps[type.rawValue] = data
            }
        }
        guard !reps.isEmpty else { return nil }

        let frontmost = NSWorkspace.shared.frontmostApplication
        return PasteboardSnapshot(
            representations: reps,
            sourceAppBundleID: frontmost?.bundleIdentifier,
            sourceAppName: frontmost?.localizedName,
            capturedAt: .now
        )
    }
}
