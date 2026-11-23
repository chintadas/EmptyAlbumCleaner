import Photos
import SwiftUI

@MainActor
@Observable
final class CleanerViewModel {
    enum Phase: Equatable {
        case needsPermission
        case limitedAccess
        case denied
        case idle
        case scanning
        case results
        case deleting
    }

    var phase: Phase = .idle
    var result = ScanResult()
    var selection = Set<String>()
    var lastMessage: String?
    var errorMessage: String?

    var allItems: [EmptyCollection] { result.emptyAlbums + result.emptyFolders }
    var selectedItems: [EmptyCollection] { allItems.filter { selection.contains($0.id) } }

    init() {
        updatePhaseForAuthorization(PhotoLibraryService.authorizationStatus)
    }

    func requestAccess() async {
        let status = await PhotoLibraryService.requestAuthorization()
        updatePhaseForAuthorization(status)
        if phase == .idle { await scan() }
    }

    /// Re-reads permission (e.g. after returning from Settings) and rescans if access was just granted.
    func refreshAuthorization() async {
        let wasBlocked = [.needsPermission, .limitedAccess, .denied].contains(phase)
        updatePhaseForAuthorization(PhotoLibraryService.authorizationStatus)
        if wasBlocked && phase == .idle { await scan() }
    }

    func scan() async {
        guard PhotoLibraryService.authorizationStatus == .authorized else {
            updatePhaseForAuthorization(PhotoLibraryService.authorizationStatus)
            return
        }
        phase = .scanning
        errorMessage = nil
        let scanned = await Task.detached(priority: .userInitiated) {
            PhotoLibraryService.scan()
        }.value
        result = scanned
        selection = Set(scanned.emptyAlbums.map(\.id) + scanned.emptyFolders.map(\.id))
        phase = .results
    }

    func deleteSelected() async {
        let items = selectedItems
        guard !items.isEmpty else { return }
        phase = .deleting
        errorMessage = nil
        do {
            let count = try await PhotoLibraryService.delete(items)
            lastMessage = count == 1 ? "Deleted 1 item." : "Deleted \(count) items."
        } catch let error as PHPhotosError where error.code == .userCancelled {
            lastMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        // Rescan: deleting albums may leave newly-empty folders behind.
        await scan()
    }

    func toggle(_ item: EmptyCollection) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func selectAll() { selection = Set(allItems.map(\.id)) }
    func selectNone() { selection.removeAll() }

    private func updatePhaseForAuthorization(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized: if phase == .needsPermission || phase == .limitedAccess || phase == .denied { phase = .idle }
        case .limited: phase = .limitedAccess
        case .notDetermined: phase = .needsPermission
        case .denied, .restricted: phase = .denied
        @unknown default: phase = .denied
        }
    }
}
