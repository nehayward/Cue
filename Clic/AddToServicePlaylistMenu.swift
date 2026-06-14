import SwiftUI
import SonosKit
import MusicSearchKit

/// Adds a track to one of the user's native Apple Music or Spotify playlists.
///
/// The menu is shown for `.apple` and `.spotify` tracks only, and targets playlists on the
/// track's own service (you can't add an Apple Music song to a Spotify playlist and vice versa).
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
                Label("No editable playlists", systemImage: "music.note.list")
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
            let created: PlayableContent?
            switch service {
            case .apple: created = await MusicSearchService.shared.createApplePlaylist(name: name)
            case .spotify: created = await MusicSearchService.shared.createSpotifyPlaylist(name: name)
            default: created = nil
            }

            guard let created else {
                await MainActor.run { showResult(success: false, playlistTitle: name) }
                return
            }

            let success = await addTrack(to: created.id)
            await MainActor.run {
                showResult(success: success, playlistTitle: created.title, created: true)
                if success { playlists.insert(created, at: 0) }
            }
        }
    }

    private func addTrack(to playlistID: String) async -> Bool {
        switch service {
        case .apple: return await MusicSearchService.shared.addToApplePlaylist(track: itemToAdd, playlistID: playlistID)
        case .spotify: return await MusicSearchService.shared.addToSpotifyPlaylist(track: itemToAdd, playlistID: playlistID)
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
