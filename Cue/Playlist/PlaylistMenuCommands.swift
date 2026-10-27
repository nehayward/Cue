import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI
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

    /// Where New Playlist makes one: the provider Browse shows, else the
    /// playing song's service, else the first provider switched on, of those
    /// whose playlists Cue can make and this device can play (the sheet
    /// names it). Never a Sonos playlist, which only a speaker plays
    /// (CLAUDE.md, Product Priorities). Nil leaves the command off.
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

    /// Opens New Playlist over whatever is on screen. The command can be
    /// chosen with the player, a sheet or any tab up, and `Router.main`'s
    /// sheet, which it used to set, has no host in the window (each tab
    /// presents from a router of its own), so it opened nothing. Presented
    /// from the top controller instead, as `PaywallPresenter` does.
    static func presentNewPlaylist() {
        guard let service = newPlaylistService else {
            AlertService.shared.showAlert(with: "No Library for a Playlist", imageName: "exclamationmark.triangle")
            return
        }
        guard let top = topController() else { return }
        // One at a time.
        if top is NewPlaylistHost { return }
        // A sheet on its way down can't be presented over: wait for it.
        if let coordinator = top.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in presentNewPlaylist() }
            return
        }
        let host = NewPlaylistHost(rootView: AnyView(NewPlaylistView(service: service).withEnvironments()))
        // SwiftUI's presentation modifiers aren't read by a controller
        // presented from UIKit, so the size is set here: the phone's detent,
        // and the card on iPad and the Mac.
        let height = NewPlaylistView.sheetHeight
        host.modalPresentationStyle = .formSheet
        host.preferredContentSize = CGSize(width: 440, height: height)
        host.sheetPresentationController?.detents = [.custom { _ in height }]
        top.present(host, animated: true)
    }

    /// The controller presented last in the active window, past any on its
    /// way down.
    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = (scene?.keyWindow ?? scene?.windows.first)?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

private final class NewPlaylistHost: UIHostingController<AnyView> {}
