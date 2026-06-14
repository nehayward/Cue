import SwiftUI
import SonosKit
import MusicSearchKit

/// Adds a track to one of the user's native Apple Music, Spotify, or Plex playlists.
///
/// The menu targets playlists on the track's own service (you can't add an Apple Music song to a
/// Spotify playlist, etc.), so it's only shown for `.apple`, `.spotify`, and `.plex` tracks.
struct AddToServicePlaylistMenu: View {
    @Environment(AlertService.self) private var alertService

    var itemToAdd: PlayableContent

    @State private var playlists: [PlayableContent] = []
    @State private var isLoading = true

    private var service: MusicService { itemToAdd.content.service }

    private var serviceName: String {
        switch service {
        case .apple: return "Apple Music"
        case .spotify: return "Spotify"
        case .plex: return "Plex"
        default: return ""
        }
    }

    var body: some View {
        Menu {
            Button {
                createPlaylistAndAdd()
            } label: {
                LabeledContent("New Playlist") {
                    Image(systemName: "plus")
                }
            }

            if isLoading {
                Label("Loading…", systemImage: "ellipsis")
            } else if playlists.isEmpty {
                Label("No playlists", systemImage: "music.note.list")
            } else {
                ForEach(playlists) { playlist in
                    Button(playlist.title) {
                        add(to: playlist)
                    }
                }
            }
        } label: {
            Label("Add to \(serviceName) Playlist", systemImage: "music.note.list")
        }
        .task {
            playlists = await fetchPlaylists()
            isLoading = false
        }
    }

    private func fetchPlaylists() async -> [PlayableContent] {
        switch service {
        case .apple: return await MusicSearchService.shared.appleUserPlaylists()
        case .spotify: return await MusicSearchService.shared.spotifyEditablePlaylists()
        case .plex: return await MusicSearchService.shared.plexUserPlaylists()
        default: return []
        }
    }

    private func add(to playlist: PlayableContent) {
        Task {
            let success = await addTrack(to: playlist.id)
            await MainActor.run { showResult(success: success, playlistTitle: playlist.title) }
        }
    }

    private func createPlaylistAndAdd() {
        Task {
            let name = itemToAdd.metadata?.album ?? itemToAdd.title
            // Each service creates the playlist and adds the track in one step.
            let created: PlayableContent?
            switch service {
            case .apple: created = await MusicSearchService.shared.createApplePlaylist(name: name, addingTrack: itemToAdd)
            case .spotify: created = await MusicSearchService.shared.createSpotifyPlaylist(name: name, addingTrack: itemToAdd)
            case .plex: created = await MusicSearchService.shared.createPlexPlaylist(name: name, track: itemToAdd)
            default: created = nil
            }

            await MainActor.run {
                showResult(success: created != nil, playlistTitle: created?.title ?? name, created: true)
                if let created { playlists.insert(created, at: 0) }
            }
        }
    }

    private func addTrack(to playlistID: String) async -> Bool {
        switch service {
        case .apple: return await MusicSearchService.shared.addToApplePlaylist(track: itemToAdd, playlistID: playlistID)
        case .spotify: return await MusicSearchService.shared.addToSpotifyPlaylist(track: itemToAdd, playlistID: playlistID)
        case .plex: return await MusicSearchService.shared.addToPlexPlaylist(track: itemToAdd, playlistID: playlistID)
        default: return false
        }
    }

    @MainActor
    private func showResult(success: Bool, playlistTitle: String, created: Bool = false) {
        if success {
            let verb = created ? "Created" : "Added to"
            alertService.showAlertContent(with: itemToAdd, subtitle: "\(verb) \(playlistTitle)", symbolName: "plus")
        } else {
            alertService.showAlert(with: "Couldn't add to \(playlistTitle)", imageName: "exclamationmark.triangle")
        }
    }
}
