import Foundation
import Observation

/// Observable data layer exposing recent history plus actions/queries. No UI state.
@MainActor
@Observable
final class ClipboardStore {

    var clips: [Clip] = []

    private let repository: ClipboardRepository
    private let pasteService: PasteService

    init(repository: ClipboardRepository, pasteService: PasteService) {
        self.repository = repository
        self.pasteService = pasteService
    }

    // MARK: - Read

    func refresh() async {
        do {
            clips = try await repository.clips(matching: [])
        } catch {
            #if DEBUG
            print("Store refresh error:", error)
            #endif
        }
    }

    func clips(matching filters: [ClipFilter]) async throws -> [Clip] {
        try await repository.clips(matching: filters)
    }

    func distinctSourceApps() async throws -> [SourceAppInfo] {
        try await repository.distinctSourceApps()
    }

    // MARK: - Mutations

    func paste(_ clip: Clip) async {
        await pasteService.paste(clip)
    }

    func delete(clipID: UUID) async {
        do {
            try await repository.delete(clipID: clipID)
            await refresh()
        } catch {
            #if DEBUG
            print("delete error:", error)
            #endif
        }
    }

    func togglePin(_ clip: Clip) async {
        do {
            try await repository.togglePin(clipID: clip.id)
            await refresh()
        } catch {
            #if DEBUG
            print("togglePin error:", error)
            #endif
        }
    }
}
