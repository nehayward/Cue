import Foundation
import SwiftUI
import SonosKit

/// Owns a playlist's in-memory track list and performs add/remove edits, registering each edit with
/// the scene's `UndoManager` so they participate in native Undo/Redo (Edit menu, ⌘Z / ⌘⇧Z, shake).
///
/// Why a reference type: `UndoManager` retains its target for as long as the action sits on the
/// stack, and a SwiftUI `View` is a value type that's constantly recreated — so the undoable
/// operations have to live on a stable object. `MediaDetailView` reads `tracks` from here.
///
/// Redo works because each undo handler re-registers its own inverse *synchronously* while
/// `UndoManager` is undoing, which routes that registration onto the redo stack. The network calls
/// are fire-and-forget `Task`s (handlers are synchronous); the in-memory list updates optimistically.
@MainActor
@Observable
final class PlaylistEditCoordinator {
    /// Shared instance for edits made outside a track-list context (e.g. the "Add to Playlist" menu).
    static let shared = PlaylistEditCoordinator()

    /// The visible track list. `MediaDetailView` binds to this.
    var tracks: [PlayableContent] = []

    /// The playlist this coordinator is editing in place. `nil` for context-free edits (e.g. the menu),
    /// where there's no on-screen list to keep in sync.
    private(set) var playlist: PlayableContent?

    private let service = MusicSearchService.shared
    private let alertService = AlertService.shared

    func configure(playlist: PlayableContent) {
        self.playlist = playlist
    }

    /// Whether this coordinator should keep its `tracks` list in sync for `playlist`.
    private func owns(_ playlist: PlayableContent) -> Bool {
        self.playlist?.content.id == playlist.content.id
    }

    // MARK: - Public entry points

    /// Removes the track at `index` from the editing playlist, with native undo + a tap-to-undo toast.
    func removeTrack(at index: Int, undoManager: UndoManager?) {
        guard let playlist, tracks.indices.contains(index) else { return }
        let track = tracks[index]
        remove(track: track, at: index, playlist: playlist, undoManager: undoManager, showToast: true)
    }

    /// Removes several selected tracks as a single undoable group.
    func removeSelected(_ indexes: [Int], undoManager: UndoManager?) {
        guard let playlist else { return }
        let items: [(track: PlayableContent, index: Int)] = indexes
            .sorted(by: >)
            .compactMap { tracks.indices.contains($0) ? (tracks[$0], $0) : nil }
        guard !items.isEmpty else { return }

        undoManager?.beginUndoGrouping()
        for item in items {
            remove(track: item.track, at: item.index, playlist: playlist, undoManager: undoManager, showToast: false)
        }
        undoManager?.setActionName(items.count == 1 ? "Remove Track" : "Remove Tracks")
        undoManager?.endUndoGrouping()

        showUndoToast(message: items.count == 1 ? "Removed \(items[0].track.title)" : "Removed \(items.count) tracks",
                      undoManager: undoManager)
    }

    /// Registers native undo for an add that already happened elsewhere (e.g. the "Add to Playlist"
    /// menu). Only meaningful where the inverse (remove) is supported — Spotify and Plex.
    func registerExternalAdd(track: PlayableContent, to playlist: PlayableContent, undoManager: UndoManager?) {
        guard [.spotify, .plex].contains(playlist.content.service) else { return }
        undoManager?.registerUndo(withTarget: self) { coordinator in
            MainActor.assumeIsolated {
                coordinator.remove(track: track, at: 0, playlist: playlist, undoManager: undoManager, showToast: false)
            }
        }
        undoManager?.setActionName("Add Track")
    }

    // MARK: - Core add / remove (each registers its own inverse)

    private func remove(track: PlayableContent, at index: Int, playlist: PlayableContent, undoManager: UndoManager?, showToast: Bool) {
        let ownsList = owns(playlist)
        if ownsList, tracks.indices.contains(index) {
            tracks.remove(at: index)
        }

        Task {
            let success = await service.removeFromServicePlaylist(track: track, playlist: playlist)
            if !success {
                if ownsList { tracks.insert(track, at: min(index, tracks.count)) }
                alertService.showAlert(with: "Couldn't remove track", imageName: "exclamationmark.triangle")
            }
        }

        undoManager?.registerUndo(withTarget: self) { coordinator in
            MainActor.assumeIsolated {
                coordinator.add(track: track, at: index, playlist: playlist, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Remove Track")

        if showToast {
            showUndoToast(message: "Removed \(track.title)", undoManager: undoManager)
        }
    }

    private func add(track: PlayableContent, at index: Int, playlist: PlayableContent, undoManager: UndoManager?) {
        let ownsList = owns(playlist)
        if ownsList {
            tracks.insert(track, at: min(index, tracks.count))
        }

        Task {
            let success = await service.addToServicePlaylist(track: track, playlist: playlist)
            if !success {
                if ownsList, let existing = tracks.firstIndex(where: { $0.trackID == track.trackID }) {
                    tracks.remove(at: existing)
                }
                alertService.showAlert(with: "Couldn't add track", imageName: "exclamationmark.triangle")
            }
        }

        undoManager?.registerUndo(withTarget: self) { coordinator in
            MainActor.assumeIsolated {
                // The row may have shifted since the add; prefer its current position.
                let currentIndex = coordinator.tracks.firstIndex(where: { $0.trackID == track.trackID }) ?? index
                coordinator.remove(track: track, at: currentIndex, playlist: playlist, undoManager: undoManager, showToast: false)
            }
        }
        undoManager?.setActionName("Add Track")
    }

    private func showUndoToast(message: String, undoManager: UndoManager?) {
        alertService.showUndoAlert(with: message) {
            undoManager?.undo()
        }
    }
}
