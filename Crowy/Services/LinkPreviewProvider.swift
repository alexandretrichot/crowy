import AppKit
import LinkPresentation
import Observation

/// In-memory cache of link previews (title + og:image) keyed by URL, backed by
/// `LPMetadataProvider`. Not persisted: we refetch on next launch.
@MainActor
@Observable
final class LinkPreviewProvider {

    struct Preview {
        let title: String?
        let image: NSImage?
    }

    /// Bumped on every insert so views observing the provider re-render.
    /// `cache` itself is `@ObservationIgnored` (dicts aren't observable natively).
    private(set) var revision: Int = 0

    @ObservationIgnored
    private var cache: [String: Preview] = [:]
    @ObservationIgnored
    private var fetching: Set<String> = []

    /// Sync read; returns `nil` if not yet fetched — caller should also call `ensureFetched`.
    func preview(for urlString: String) -> Preview? {
        _ = revision  // register observation dependency
        return cache[urlString]
    }

    /// Idempotent — safe to call from `.task` / `.onAppear` on every render.
    func ensureFetched(for urlString: String) {
        guard cache[urlString] == nil,
              !fetching.contains(urlString),
              let url = URL(string: urlString),
              url.scheme?.hasPrefix("http") == true else { return }

        fetching.insert(urlString)

        let provider = LPMetadataProvider()
        provider.timeout = 8
        provider.startFetchingMetadata(for: url) { [weak self] metadata, _ in
            // Callback runs on a private queue; hop back to MainActor.
            let title = metadata?.title

            if let imageProvider = metadata?.imageProvider {
                imageProvider.loadObject(ofClass: NSImage.self) { [weak self] object, _ in
                    Task { @MainActor [weak self] in
                        self?.complete(urlString, Preview(title: title, image: object as? NSImage))
                    }
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.complete(urlString, Preview(title: title, image: nil))
                }
            }
        }
    }

    private func complete(_ urlString: String, _ preview: Preview) {
        cache[urlString] = preview
        fetching.remove(urlString)
        revision += 1
    }
}
