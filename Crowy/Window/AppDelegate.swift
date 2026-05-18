import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Exposed so `CrowyApp` can inject them into the SwiftUI Window scenes.
    // Both `@Observable`; bindings flow back automatically.
    let preferences = Preferences()
    let permissions = PermissionsManager()

    private var database: Database!
    private var blobStore: BlobStore!
    private var repository: ClipboardRepository!
    private var store: ClipboardStore!
    private var ingestor: ClipboardIngestor!
    private var monitor: ClipboardMonitor!
    private var retentionJob: RetentionJob!
    private var pasteService: PasteService!
    private let iconProvider = AppIconProvider()
    private let linkPreviewProvider = LinkPreviewProvider()
    private var panel: PastePanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            database = try Database()
            blobStore = try BlobStore(rootURL: AppPaths.blobStoreRoot)
        } catch {
            fatalError("Failed to initialize storage: \(error)")
        }

        repository = ClipboardRepository(database: database, blobStore: blobStore)

        // The panel doesn't exist yet, so we inject a closure that looks up
        // `self.panel` lazily; by the time the user pastes, `self.panel` is populated.
        pasteService = PasteService(
            repository: repository,
            onWillPaste: { [weak self] in self?.panel?.hide(animated: true) },
            onAccessibilityMissing: { [weak self] in self?.permissions.requestAccessibility() }
        )

        store = ClipboardStore(repository: repository, pasteService: pasteService)

        // Filter pipeline: a snapshot must pass all three to be ingested.
        // Ordered by ascending cost (cheap checks first).
        let filter = CompositeFilter(filters: [
            NSPasteboardConventionsFilter(),
            InternalMarkerFilter(),
            BlacklistFilter(blacklistedBundleIDs: { [preferences] in
                preferences.blacklistedBundleIDs
            }),
        ])

        ingestor = ClipboardIngestor(repository: repository, filter: filter)
        monitor = ClipboardMonitor()
        retentionJob = RetentionJob(repository: repository, preferences: preferences)

        // Event pipeline: Monitor -> Ingestor -> Repository -> Store.refresh()
        //                 RetentionJob -> Repository -> Store.refresh()
        monitor.onNewSnapshot = { [weak self] snapshot in
            self?.ingestor.ingest(snapshot)
        }
        ingestor.onClipInserted = { [weak self] in
            Task { @MainActor in
                await self?.store.refresh()
            }
        }
        retentionJob.onClipsDeleted = { [weak self] in
            Task { @MainActor in
                await self?.store.refresh()
            }
        }

        Task { @MainActor in
            await store.refresh()
        }

        // Build the SwiftUI root for the paste panel. PastePanel must stay an
        // NSPanel — no SwiftUI scene exposes `.nonactivatingPanel` + `.floating`
        // + `canJoinAllSpaces`, which are the panel's reason for existing.
        let rootView = PasteBarView(
            store: store,
            preferences: preferences,
            onClose: { [weak self] in self?.panel?.hide(animated: true) },
            registerDeleteHandler: { [weak self] handler in
                self?.panel?.onDeleteOutsideTextEditing = handler
            }
        )
        .environment(iconProvider)
        .environment(linkPreviewProvider)

        let panel = PastePanel(rootView: rootView)
        self.panel = panel

        HotkeyManager.shared.register(binding: preferences.hotkey) { [weak self] in
            self?.panel?.toggle()
        }

        // Reconcile the persisted preference with SMAppService's actual state on launch.
        LaunchAtLoginManager.syncPreference(preferences)

        monitor.start()
        retentionJob.start()

        // First launch only: if Accessibility is missing, show the onboarding window
        // so the user knows what to do. Otherwise launch silently — the panel
        // appears on demand via the global hotkey or app reactivation.
        //
        // Deferred to the next runloop tick: SwiftUI needs to build the commands
        // menu first (that's where AppWindowBridge.openOnboarding gets wired).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.permissions.isAccessibilityGranted {
                AppWindowBridge.shared.openOnboarding()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Called when the user re-activates an already-running app (Spotlight Enter,
    /// Dock click while Settings is open, Finder double-click on Crowy.app).
    /// Surface the paste panel — it's the most likely thing they want.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if let panel, !panel.isVisible {
            panel.show(animated: true)
        }
        return false
    }

    // MARK: - Hooks called by SwiftUI scenes

    /// Settings: hotkey changed → re-register the Carbon hotkey with the new binding.
    func handleHotkeyChange(_ binding: HotkeyBinding) {
        HotkeyManager.shared.register(binding: binding) { [weak self] in
            self?.panel?.toggle()
        }
    }

    /// Onboarding window closed (continue / red-X / auto-dismiss on grant).
    /// No-op: the user discovers the panel via the global hotkey or by
    /// reactivating the app — consistent with the launch behavior.
    func completeOnboarding() {}
}
