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
        let ownsList = owns(playlist)
        let items: [(track: PlayableContent, index: Int)] = indexes
            .sorted(by: >)
            .compactMap { tracks.indices.contains($0) ? (tracks[$0], $0) : nil }
        guard !items.isEmpty else { return }

        // Optimistic removal + undo registration, highest index first so the remaining indices stay valid.
        undoManager?.beginUndoGrouping()
        for item in items {
            if ownsList, tracks.indices.contains(item.index) {
                tracks.remove(at: item.index)
            }
            registerRemoveUndo(track: item.track, at: item.index, playlist: playlist, undoManager: undoManager)
        }
        undoManager?.setActionName(items.count == 1 ? "Remove Track" : "Remove Tracks")
        undoManager?.endUndoGrouping()

        // Network removals run sequentially, highest playlist position first, so each positional
        // delete (Spotify) sees an unshifted index — concurrent deletes would race on stale positions.
        Task {
            for item in items {
                await performRemoval(track: item.track, at: item.index, playlist: playlist, ownsList: ownsList)
            }
        }

        if supportsUndo(playlist) {
            showUndoToast(message: items.count == 1 ? "Removed \(items[0].track.title)" : "Removed \(items.count) tracks",
                          undoManager: undoManager)
        }
    }

    /// Reorders a track within the editing playlist, optimistically updating the visible list and
    /// reverting if the service rejects the move. Reorder isn't undoable (parity with Sonos move).
    func moveTrack(from source: IndexSet, to destination: Int, playlist: PlayableContent) {
        guard owns(playlist), let sourceIndex = source.first else { return }
        let previous = tracks
        tracks.move(fromOffsets: source, toOffset: destination)
        let reordered = tracks

        Task {
            let success: Bool
            if playlist.isSonosPlaylist {
                success = (try? await SonosService.shared.reorderPlaylist(playlistID: playlist.content.id, from: sourceIndex, to: destination)) != nil
            } else {
                success = await service.reorderServicePlaylist(playlist: playlist, orderedTracks: reordered, from: sourceIndex, to: destination)
            }
            if !success {
                tracks = previous
                alertService.showAlert(with: "Couldn't reorder track", imageName: "exclamationmark.triangle")
            }
        }
    }

    /// Whether removals from `playlist` can be undone. Sonos has no positional re-add (its add
    /// appends), so Sonos edits are not undoable — only the streaming services are.
    private func supportsUndo(_ playlist: PlayableContent) -> Bool {
        [.spotify, .plex, .deezer].contains(playlist.content.service)
    }

    /// Registers a main-actor undo handler with `undoManager`. The single `assumeIsolated` lives
    /// here: `UndoManager` runs handlers synchronously on whatever thread calls `undo()`/`redo()`,
    /// which is always main here (toast tap, the ⌘Z buttons, shake, the Edit menu). Running
    /// synchronously (vs. a `Task`) is what lets each handler re-register its inverse onto the redo
    /// stack. The handler receives the coordinator so `UndoManager` holds the only strong reference.
    private func registerUndo(undoManager: UndoManager?, _ body: @escaping @MainActor (PlaylistEditCoordinator) -> Void) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { body(target) }
        }
    }

    /// Registers native undo for an add that already happened elsewhere (e.g. the "Add to Playlist"
    /// menu). Only meaningful where the inverse (remove) is supported — Spotify, Plex, and Deezer.
    func registerExternalAdd(track: PlayableContent, to playlist: PlayableContent, undoManager: UndoManager?) {
        guard supportsUndo(playlist) else { return }
        registerUndo(undoManager: undoManager) {
            $0.remove(track: track, at: 0, playlist: playlist, undoManager: undoManager, showToast: false)
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
            await performRemoval(track: track, at: index, playlist: playlist, ownsList: ownsList)
        }

        registerRemoveUndo(track: track, at: index, playlist: playlist, undoManager: undoManager)
        undoManager?.setActionName("Remove Track")

        if showToast, supportsUndo(playlist) {
            showUndoToast(message: "Removed \(track.title)", undoManager: undoManager)
        }
    }

    /// Performs the removal and rolls the optimistic UI back on failure. `index` is the track's
    /// playlist position; for Sonos it identifies the row to drop, and for Spotify it lets the
    /// service remove a single occurrence instead of every copy (only when this coordinator owns
    /// the on-screen list).
    private func performRemoval(track: PlayableContent, at index: Int, playlist: PlayableContent, ownsList: Bool) async {
        let success: Bool
        if playlist.isSonosPlaylist {
            success = (try? await SonosService.shared.removeTrackFromPlaylist(playlistID: playlist.content.id, index: index)) != nil
        } else {
            let position = ownsList ? index : nil
            success = await service.removeFromServicePlaylist(track: track, playlist: playlist, position: position)
        }
        if !success {
            if ownsList { tracks.insert(track, at: min(index, tracks.count)) }
            alertService.showAlert(with: "Couldn't remove track", imageName: "exclamationmark.triangle")
        }
    }

    /// Registers the inverse (re-add) of a removal with the undo manager, where the service supports it.
    private func registerRemoveUndo(track: PlayableContent, at index: Int, playlist: PlayableContent, undoManager: UndoManager?) {
        guard supportsUndo(playlist) else { return }
        registerUndo(undoManager: undoManager) {
            $0.add(track: track, at: index, playlist: playlist, undoManager: undoManager)
        }
    }

    private func add(track: PlayableContent, at index: Int, playlist: PlayableContent, undoManager: UndoManager?) {
        let ownsList = owns(playlist)
        let insertIndex = min(index, tracks.count)
        if ownsList {
            tracks.insert(track, at: insertIndex)
        }

        Task {
            let success = await service.addToServicePlaylist(track: track, playlist: playlist)
            if !success {
                // Remove the copy we inserted — prefer the insertion slot if it still holds it, so a
                // pre-existing duplicate of the same track isn't deleted instead.
                if ownsList {
                    if tracks.indices.contains(insertIndex), tracks[insertIndex].trackID == track.trackID {
                        tracks.remove(at: insertIndex)
                    } else if let existing = tracks.firstIndex(where: { $0.trackID == track.trackID }) {
                        tracks.remove(at: existing)
                    }
                }
                alertService.showAlert(with: "Couldn't add track", imageName: "exclamationmark.triangle")
            }
        }

        registerUndo(undoManager: undoManager) { coordinator in
            // The row may have shifted since the add; prefer its current position.
            let currentIndex = coordinator.tracks.firstIndex(where: { $0.trackID == track.trackID }) ?? index
            coordinator.remove(track: track, at: currentIndex, playlist: playlist, undoManager: undoManager, showToast: false)
        }
        undoManager?.setActionName("Add Track")
    }

    private func showUndoToast(message: String, undoManager: UndoManager?) {
        alertService.showUndoAlert(with: message) {
            undoManager?.undo()
        }
    }
}
