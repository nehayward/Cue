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

struct SpotifySearchScreen: View {
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SpotifyBrowseService.self) private var spotifyBrowseService
    
    var body: some View {
        Section {
            NavigationLink(value: RouterDestination.playableList(title: "Songs", playAllItem: .spotifyLikes, showSectionIndex: false, action: { offset in
                await spotifyBrowseService.updateSongs()
                return Array(spotifyBrowseService.tracks)
            })) {
                Text("Liked Songs")
                    .fontDesign(.rounded)
                    .fontWeight(.semibold)
            }
            .tag(UUID().uuidString)
            ScrollView(.vertical) {
                LazyVGrid(columns: [.init(), .init()]) {
                    ForEach(spotifyBrowseService.tracks.prefix(7)) { item in
                        PlayableContentRowView(item: item)
                            .buttonStyle(.plain)
                    }
                    if !spotifyBrowseService.tracks.isEmpty {
                        PlayAllButtonView(item: .spotifyLikes)
                    }
                }
            }
        }
        .listRowInsets(.default)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .task {
            await spotifyBrowseService.updateSongs(offset: 0, limit: 10)
        }
        .listRowSpacing(0)
        
        Section {
            NavigationLink(value: RouterDestination.playableList(title: "Spotify Playlists", showSectionIndex: false, action: { offset in
                await spotifyBrowseService.updatePlaylists(offset: offset)
                return Array(spotifyBrowseService.playlists)
            })) {
                Text("Playlists")
                    .fontDesign(.rounded)
                    .fontWeight(.semibold)
            }
            .tag(UUID().uuidString)
            
            ScrollView(.vertical) {
                LazyVGrid(columns: [.init(), .init()]) {
                    ForEach(spotifyBrowseService.playlists.prefix(8)) { item in
                        PlayableContentRowView(item: item)
                    }
                }
            }
            .listRowInsets(.default)
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .task {
            await spotifyBrowseService.updatePlaylists(offset: 0, limit: 10)
        }
        
        Section {
            NavigationLink(value: RouterDestination.playableList(title: "Spotify Albums", showSectionIndex: false, action: { offset in
                await spotifyBrowseService.userAlbums(offset: offset, limit: 25)
                return Array(spotifyBrowseService.albums)
            })) {
                Text("Albums")
                    .fontDesign(.rounded)
                    .fontWeight(.semibold)
            }
            .tag(UUID().uuidString)
            
            ForEach(spotifyBrowseService.albums.prefix(5)) { item in
                PlayableContentRowView(item: item)
                    .padding(.bottom, 8)
            }
        }
        .listRowInsets(.default)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .task {
            await spotifyBrowseService.userAlbums(offset: 0, limit: 10)
        }
    }
    
}

#Preview {
    List {
        SpotifySearchScreen()
    }
    .forPreview()
    .listStyle(.plain)
}
