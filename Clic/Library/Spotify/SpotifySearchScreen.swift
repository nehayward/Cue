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
import TipKit

struct SpotifySearchScreen: View {
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SpotifyBrowseService.self) private var spotifyBrowseService
        
    var body: some View {
        if !spotifyBrowseService.tracks.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(spotifyBrowseService.tracks.prefix(10)) { item in
                            PlayableArtworkView(item: item)
                                .containerRelativeFrame(.horizontal, count: 4, spacing: 4)
                                .listRowInsets(EdgeInsets())
                        }
                        NavigationLink(value: RouterDestination.playableList(title: "Songs", action: { offset in
                            await spotifyBrowseService.updateSongs()
                            return Array(spotifyBrowseService.tracks)
                        })) {
                            Text("All Songs")
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            } header: {
                NavigationLink(value: RouterDestination.playableList(title: "Songs", action: { offset in
                    await spotifyBrowseService.updateSongs()
                    return Array(spotifyBrowseService.tracks)
                })) {
                    Label("Songs", systemImage: "music.note")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .task {
                await spotifyBrowseService.updateSongs(offset: 0, limit: 10)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .task {
                    await spotifyBrowseService.updateSongs(offset: 0, limit: 10)
                }
        }
        
        if !spotifyBrowseService.playlists.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(spotifyBrowseService.playlists.prefix(10)) { item in
                            PlayableArtworkView(item: item)
                                .containerRelativeFrame(.horizontal, count: 4, spacing: 4)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            } header: {
                NavigationLink(value: RouterDestination.playableList(title: "Spotify Playlists", action: { offset in
                    print(offset)
                    await spotifyBrowseService.updatePlaylists()
                    return Array(spotifyBrowseService.playlists)
                })) {
                    Label("Playlists", systemImage: "rectangle.stack.badge.play")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .task {
                await spotifyBrowseService.updatePlaylists(offset: 0, limit: 10)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .task {
                    await spotifyBrowseService.updatePlaylists(offset: 0, limit: 10)
                }
        }
        
        if !spotifyBrowseService.albums.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(spotifyBrowseService.albums.prefix(10)) { item in
                            PlayableArtworkView(item: item)
                                .containerRelativeFrame(.horizontal, count: 4, spacing: 4)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            } header: {
                NavigationLink(value: RouterDestination.playableList(title: "Spotify Albums", action: { offset in
                    print(offset)
                    await spotifyBrowseService.userAlbums()
                    return Array(spotifyBrowseService.albums)
                })) {
                    Label("Albums", systemImage: "smallcircle.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.secondary)
                }
            }
            .task {
                await spotifyBrowseService.userAlbums(offset: 0, limit: 10)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .task {
                    await spotifyBrowseService.userAlbums(offset: 0, limit: 10)
                }
        }
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}
