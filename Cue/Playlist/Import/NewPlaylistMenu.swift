import SonosKit
import SwiftUI

/// The plus on a service's playlists: a new playlist, or — where a playlist
/// can be imported into that service — one brought across from Spotify,
/// Apple Music or a file.
struct NewPlaylistMenu: View {
    let service: MusicService
    let newPlaylist: () -> Void
    let importPlaylist: () -> Void

    var body: some View {
        if PlaylistImporter.destinations.contains(service) {
            Menu {
                Button(action: newPlaylist) {
                    Label("New Playlist", systemImage: "plus")
                }
                Button {
                    if FeatureGate.shared.unlock(.importPlaylists) {
                        importPlaylist()
                    }
                } label: {
                    Label("Import Playlist…", systemImage: "square.and.arrow.down")
                }
            } label: {
                Label("New Playlist", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
        } else {
            Button(action: newPlaylist) {
                Label("New Playlist", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
        }
    }
}
