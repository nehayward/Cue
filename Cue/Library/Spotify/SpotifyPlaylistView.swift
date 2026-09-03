import Analytics
import CloudStorage
import MusicSearchKit
import Defaults
import NukeUI
import MusicKit
import OrderedCollections
import SwiftUI
import SonosKit
import Defaults

struct SpotifyUsersPlaylistView: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(SpotifyBrowseService.self) private var spotifyBrowseService: SpotifyBrowseService
    @Environment(Router.self) private var router

    var playlistCountLimit: Int = 5
    var hideNavigation: Bool = false
    
    @AppStorage("spotify.userID.cue") private var userID: String = ""
    @State private var isLoading: Bool = false
    
    var body: some View {
        @Bindable var sonosService = sonosService
        
        if !hideNavigation {
            NavigationLink(value: RouterDestination.spotifyUserPlaylist) {
                Text("My Playlists")
                    .foregroundStyle(.secondary)
                    .fontDesign(.rounded)
                    .bold()
            }
            .listRowSeparator(.hidden)
            .task {
                await updateSpotifyBrowseService()
            }
        }
        
        if !spotifyBrowseService.userPlaylists.isEmpty {
            ForEach(spotifyBrowseService.userPlaylists.prefix(playlistCountLimit)) { item in
                PlayableContentView(item: item)
            }
        } else {
            if isLoading, spotifyBrowseService.userPlaylists.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        
        if userID.isEmpty {
            Button {
                router.presentedSheet = .spotifyUserPlaylists
            } label: {
                Text("Add Your Spotify Username to show playlists")
            }
        }
    }
    
    @MainActor
    private func updateSpotifyBrowseService() async {
        isLoading = true
        defer { isLoading = false }
        if userID.isEmpty { return }
        await spotifyBrowseService.updateUsersRecentPlayed(userID: userID)
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}
