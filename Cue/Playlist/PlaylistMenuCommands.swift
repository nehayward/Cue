import Defaults
import MusicSearchKit
import Observation
import SonosKit
import UIKit

/// What the menu bar's Playlist menu acts on (`AppDelegate.buildMenu`, on
/// iPad and the Mac): the song the player shows, on this device or a
/// speaker, and the service a new playlist goes to. The menu used to read
/// only the selected Sonos group, so with music on this device Add to Last
/// Playlist and Add to Playlist had nothing to add.
@MainActor
enum PlaylistMenuCommands {
    /// The song the player shows, when it can go in a playlist: the song on
    /// air while a station plays and Apple Music has it, never a station
    /// itself or a book's file (the player's menu offers neither).
    static var songToAdd: PlayableContent? {
        let presented = PlaybackRoute.shared.presented
        let song: PlayableContent?
        if presented.group != nil {
            song = presented.nowPlayingDisplay
        } else {
            let local = LocalPlaybackService.shared
            song = local.onAirMatch ?? local.nowPlaying
        }
        guard let song, !song.content.type.isRadio, !AudiobookPlayer.shared.contains(song) else { return nil }
        return song
    }

    /// Whether Add to Last Playlist has something to do: a last playlist, and
    /// a song playing that can go in it.
    static var canAddToLastPlaylist: Bool {
        guard let last = LastPlaylist.current, let song = songToAdd else { return false }
        return last.accepts(song)
    }

    /// What the menu bar's Add to Last Playlist was last built with.
    private static var menuCanAdd: Bool?

    /// Called as the menu is built: whether its Add to Last Playlist is on,
    /// kept to compare with what's playing from then on.
    static func noteMenuBuilt() -> Bool {
        let canAdd = canAddToLastPlaylist
        menuCanAdd = canAdd
        return canAdd
    }

    /// Keeps Add to Last Playlist on or off with what's playing, from launch.
    /// SwiftUI's app delegate stands in the responder chain in place of Cue's,
    /// so `AppDelegate.canPerformAction` is never asked as the menu opens: the
    /// command is built on or off instead, and the menu rebuilt when what's
    /// playing turns it the other way. `LastPlaylist.save` rebuilds it for a
    /// new last playlist.
    static func followAddToLastPlaylist() {
        let canAdd = withObservationTracking {
            canAddToLastPlaylist
        } onChange: {
            Task { @MainActor in followAddToLastPlaylist() }
        }
        if let menuCanAdd, menuCanAdd != canAdd {
            UIMenuSystem.main.setNeedsRebuild()
        }
    }

    /// Where New Playlist makes one: the provider Browse shows, else the
    /// playing song's service, else the first provider switched on, of those
    /// whose playlists Cue can make and this device can play (the sheet
    /// names it). Never a Sonos playlist, which only a speaker plays
    /// (CLAUDE.md, Product Priorities). Nil when none is switched on.
    static var newPlaylistService: MusicService? {
        let browsed = UserDefaults.standard.string(forKey: AppStorageKeys.browseMediaService)
            .flatMap(MediaSearchService.init(rawValue:)) ?? .apple
        if let service = playlistService(for: browsed) {
            return service
        }
        if let service = songToAdd?.content.service, makesPlaylists.contains(service) {
            return service
        }
        return MediaSearchService.supported.compactMap(playlistService(for:)).first
    }

    private static let makesPlaylists: [MusicService] = [.apple, .plex, .subsonic, .files]

    /// The service a provider's playlists are made on, while it's switched on.
    private static func playlistService(for provider: MediaSearchService) -> MusicService? {
        guard CoreFeatures.shared.isEnabled(provider) else { return nil }
        return switch provider {
        case .apple: .apple
        case .plex: .plex
        case .subsonic: .subsonic
        case .files: .files
        default: nil
        }
    }

    /// Asks for the new playlist's name in an alert over whatever is on
    /// screen. The command can be chosen with the player, a sheet or any tab
    /// up, and `Router.main`'s sheet, which it used to set, has no host in
    /// the window (each tab presents from a router of its own), so it opened
    /// nothing. Presented from the top controller instead, as
    /// `PaywallPresenter` does. An alert rather than `NewPlaylistView`: a
    /// SwiftUI view presented from UIKit doesn't read its own sheet
    /// modifiers, and came out on iPad as a small glass card with an empty
    /// bar over it. Return creates, Escape cancels.
    static func presentNewPlaylist() {
        guard let service = newPlaylistService else {
            AlertService.shared.showAlert(with: "No Library for a Playlist", imageName: "exclamationmark.triangle")
            return
        }
        guard let top = TopViewController.current else { return }
        // One at a time.
        if top is UIAlertController { return }
        // A sheet on its way down can't be presented over: wait for it.
        if let coordinator = top.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in presentNewPlaylist() }
            return
        }
        let alert = UIAlertController(title: NewPlaylistView.title(for: service), message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Playlist Title"
            field.autocapitalizationType = .words
            field.returnKeyType = .done
        }
        let enteredName: () -> String = { [weak alert] in
            alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let create = UIAlertAction(title: "Create", style: .default) { _ in
            let name = enteredName()
            guard !name.isEmpty else { return }
            Task { @MainActor in
                await NewPlaylistView.create(named: name, on: service)
            }
        }
        // Off until there's a name, as the sheet's Create is.
        create.isEnabled = false
        alert.textFields?.first?.addAction(UIAction { [weak create] _ in
            create?.isEnabled = !enteredName().isEmpty
        }, for: .editingChanged)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(create)
        alert.preferredAction = create
        top.present(alert, animated: true)
    }
}
