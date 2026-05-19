import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

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
    private var onboardingPanel: AccessoryPanel?

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

        // Onboarding stays in an NSPanel so it can show without a Dock icon.
        // Settings is a SwiftUI `Window` scene for the native macOS 26 Liquid
        // Glass chrome — its `openSettings` closure is wired by `PasteBarView`
        // (the only place we can capture `@Environment(\.openWindow)`).
        AppWindowBridge.shared.openOnboarding = { [weak self] in self?.showOnboarding() }

        // First launch only: if Accessibility is missing, show the onboarding panel
        // so the user knows what to do. Otherwise launch silently — the paste panel
        // appears on demand via the global hotkey or app reactivation.
        if !permissions.isAccessibilityGranted {
            showOnboarding()
        }

        // Defensive: SwiftUI's stub WindowGroup can flip activation policy to
        // .regular during its setup. Re-assert on the next runloop tick to keep
        // the Dock icon hidden.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
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

    // MARK: - Onboarding panel

    private func showOnboarding() {
        if onboardingPanel == nil {
            onboardingPanel = AccessoryPanel(
                rootView: OnboardingView(
                    permissions: permissions,
                    hotkey: preferences.hotkey,
                    onPermissionGranted: { [weak self] in self?.onboardingPanel?.show() },
                    onDismiss: { [weak self] in self?.onboardingPanel?.hide() }
                ),
                title: "Welcome to Crowy",
                contentSize: NSSize(width: 480, height: 560),
                resizable: false
            )
        }
        onboardingPanel?.show()
    }

    // MARK: - Hooks called by the SwiftUI Settings scene

    /// Settings: hotkey changed → re-register the Carbon hotkey with the new binding.
    func handleHotkeyChange(_ binding: HotkeyBinding) {
        HotkeyManager.shared.register(binding: binding) { [weak self] in
            self?.panel?.toggle()
        }
    }
}
