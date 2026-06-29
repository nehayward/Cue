import Foundation
import SwiftUI
import SonosKit

/// Owns a playlist's in-memory track list, performs add/remove/reorder edits, and keeps its own
/// undo/redo stack. Each reversible edit pushes a step holding how to undo *and* redo it;
/// `undo()`/`redo()` just move a step between the two stacks and run the matching closure.
///
/// We use an owned stack rather than `UndoManager` because every entry point (the tap-to-undo
/// toast, the iOS ⌘Z buttons, the Catalyst Edit menu) is wired by hand anyway, and an owned stack
/// sidesteps the responder-chain / environment-manager mismatch that left `UndoManager`'s native
/// menu items permanently disabled on Catalyst. `canUndo`/`canRedo` are observed, so the UI that
/// gates on them updates automatically.
///
/// Why a reference type: the steps capture this coordinator and `MediaDetailView` reads `tracks`
/// from here, so the editor must outlive the value-type View.
@MainActor
@Observable
final class PlaylistEditCoordinator {
    /// The visible track list. `MediaDetailView` binds to this.
    var tracks: [PlayableContent] = []

    /// The playlist this coordinator is editing in place. `nil` for context-free edits (e.g. the
    /// menu), where there's no on-screen list to keep in sync.
    private(set) var playlist: PlayableContent?

    private let service = MusicSearchService.shared
    private let alertService = AlertService.shared

    // MARK: - Undo / redo stack

    private struct EditStep {
        let name: String
        let undo: @MainActor () -> Void
        let redo: @MainActor () -> Void
    }
    private var undoStack: [EditStep] = []
    private var redoStack: [EditStep] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let step = undoStack.popLast() else { return }
        step.undo()
        redoStack.append(step)
    }

    func redo() {
        guard let step = redoStack.popLast() else { return }
        step.redo()
        undoStack.append(step)
    }

    /// Records a reversible edit. A fresh edit invalidates the redo history.
    private func pushStep(name: String, undo: @escaping @MainActor () -> Void, redo: @escaping @MainActor () -> Void) {
        undoStack.append(EditStep(name: name, undo: undo, redo: redo))
        redoStack.removeAll()
    }

    func configure(playlist: PlayableContent) {
        if self.playlist?.content.id != playlist.content.id {
            // Switching playlists: the previous edit history no longer applies.
            undoStack.removeAll()
            redoStack.removeAll()
        }
        self.playlist = playlist
    }

    /// Whether this coordinator should keep its `tracks` list in sync for `playlist`.
    private func owns(_ playlist: PlayableContent) -> Bool {
        self.playlist?.content.id == playlist.content.id
    }

    /// Whether removals from `playlist` can be undone. Sonos has no positional re-add (its add
    /// appends), so Sonos edits are not undoable — only the streaming services are.
    private func supportsUndo(_ playlist: PlayableContent) -> Bool {
        [.spotify, .plex, .deezer].contains(playlist.content.service)
    }

    // MARK: - Public entry points

    /// Removes the track at `index` from the editing playlist, with a tap-to-undo toast.
    func removeTrack(at index: Int) {
        guard let playlist, tracks.indices.contains(index) else { return }
        let items = [(track: tracks[index], index: index)]
        let ownsList = owns(playlist)
        removeBatch(items, playlist: playlist, ownsList: ownsList)

        if supportsUndo(playlist) {
            pushStep(
                name: "Remove Track",
                undo: { [weak self] in self?.addBatch(items, playlist: playlist, ownsList: ownsList) },
                redo: { [weak self] in self?.removeBatch(items, playlist: playlist, ownsList: ownsList) }
            )
            showUndoToast(message: "Removed \(items[0].track.title)")
        }
    }

    /// Removes several selected tracks as a single undoable edit.
    func removeSelected(_ indexes: [Int]) {
        guard let playlist else { return }
        // Descending so removals/re-adds keep the remaining indices valid (UI + Spotify positions).
        let items: [(track: PlayableContent, index: Int)] = indexes
            .sorted(by: >)
            .compactMap { tracks.indices.contains($0) ? (tracks[$0], $0) : nil }
        guard !items.isEmpty else { return }
        let ownsList = owns(playlist)
        removeBatch(items, playlist: playlist, ownsList: ownsList)

        if supportsUndo(playlist) {
            pushStep(
                name: items.count == 1 ? "Remove Track" : "Remove Tracks",
                undo: { [weak self] in self?.addBatch(items, playlist: playlist, ownsList: ownsList) },
                redo: { [weak self] in self?.removeBatch(items, playlist: playlist, ownsList: ownsList) }
            )
            showUndoToast(message: items.count == 1 ? "Removed \(items[0].track.title)" : "Removed \(items.count) tracks")
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

    // MARK: - Batch operations (optimistic UI + network, no undo bookkeeping)

    /// Removes `items` (sorted by index descending). Network calls run sequentially so each
    /// positional removal (Spotify) sees an unshifted index — concurrent deletes would race.
    private func removeBatch(_ items: [(track: PlayableContent, index: Int)], playlist: PlayableContent, ownsList: Bool) {
        if ownsList {
            for item in items where tracks.indices.contains(item.index) {
                tracks.remove(at: item.index)
            }
        }
        Task {
            for item in items {
                await performRemoval(track: item.track, at: item.index, playlist: playlist, ownsList: ownsList)
            }
        }
    }

    /// Re-adds `items` (sorted by index descending) — the inverse of `removeBatch`. Inserts lowest
    /// index first so each lands at its original slot.
    private func addBatch(_ items: [(track: PlayableContent, index: Int)], playlist: PlayableContent, ownsList: Bool) {
        let ascending = Array(items.reversed())
        if ownsList {
            for item in ascending {
                tracks.insert(item.track, at: min(item.index, tracks.count))
            }
        }
        Task {
            for item in ascending {
                await performAdd(track: item.track, at: item.index, playlist: playlist, ownsList: ownsList)
            }
        }
    }

    private func performRemoval(track: PlayableContent, at index: Int, playlist: PlayableContent, ownsList: Bool) async {
        let success: Bool
        if playlist.isSonosPlaylist {
            success = (try? await SonosService.shared.removeTrackFromPlaylist(playlistID: playlist.content.id, index: index)) != nil
        } else {
            // `index` is the track's playlist position, letting Spotify remove a single occurrence
            // instead of every copy — only meaningful when we own the on-screen list.
            let position = ownsList ? index : nil
            success = await service.removeFromServicePlaylist(track: track, playlist: playlist, position: position)
        }
        if !success {
            if ownsList { tracks.insert(track, at: min(index, tracks.count)) }
            alertService.showAlert(with: "Couldn't remove track", imageName: "exclamationmark.triangle")
        }
    }

    private func performAdd(track: PlayableContent, at index: Int, playlist: PlayableContent, ownsList: Bool) async {
        let success = await service.addToServicePlaylist(track: track, playlist: playlist)
        if !success {
            // Remove the copy we inserted — prefer the insertion slot if it still holds it, so a
            // pre-existing duplicate of the same track isn't deleted instead.
            if ownsList {
                let insertIndex = min(index, tracks.count - 1)
                if tracks.indices.contains(insertIndex), tracks[insertIndex].trackID == track.trackID {
                    tracks.remove(at: insertIndex)
                } else if let existing = tracks.firstIndex(where: { $0.trackID == track.trackID }) {
                    tracks.remove(at: existing)
                }
            }
            alertService.showAlert(with: "Couldn't add track", imageName: "exclamationmark.triangle")
        }
    }

    private func showUndoToast(message: String) {
        alertService.showUndoAlert(with: message) { [weak self] in
            self?.undo()
        }
    }
}

/// Bridges the foreground playlist editor to the Catalyst Edit-menu commands, which dispatch
/// through the UIKit responder chain (the app delegate) rather than SwiftUI. `MediaDetailView`
/// points this at its editor while on screen; the app delegate's Undo/Redo route here.
@MainActor
final class PlaylistUndoMenuBridge {
    static let shared = PlaylistUndoMenuBridge()
    /// Weak: the editor is owned by the view, so a dismissed screen's editor simply drops out.
    weak var editor: PlaylistEditCoordinator?
}
