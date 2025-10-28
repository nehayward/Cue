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
                    LazyHStack {
                        ForEach(spotifyBrowseService.tracks.prefix(10)) { item in
                            VStack {
                                PlayableArtworkView(item: item)
                                Text(item.title)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .lineLimit(2, reservesSpace: true)
                                    .fontDesign(.rounded)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .containerRelativeFrame(
                                .horizontal, alignment: .topLeading
                            ) { length, axis in
                                if axis == .vertical {
                                    return length / 3.0
                                } else {
                                    return length / 4.5
                                }
                            }
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
                NavigationLink(value: RouterDestination.playableList(title: "Songs", playAllItem: .spotifyLikes, action: { offset in
                    await spotifyBrowseService.updateSongs()
                    return Array(spotifyBrowseService.tracks)
                })) {
                    HStack(spacing: 2) {
                        Text("Liked Songs")
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                .listRowSeparator(.hidden)
        }
        
        if !spotifyBrowseService.playlists.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    LazyHStack {
                        ForEach(spotifyBrowseService.playlists.prefix(10)) { item in
                            VStack {
                                PlayableArtworkView(item: item)
                                Text(item.title)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .lineLimit(2, reservesSpace: true)
                                    .fontDesign(.rounded)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .containerRelativeFrame(
                                .horizontal, alignment: .topLeading
                            ) { length, axis in
                                if axis == .vertical {
                                    return length / 3.0
                                } else {
                                    return length / 2.5
                                }
                            }
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
                    HStack(spacing: 2) {
                        Text("Playlists")
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                .listRowSeparator(.hidden)
        }
        
        if !spotifyBrowseService.albums.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    LazyHStack {
                        ForEach(spotifyBrowseService.albums.prefix(10)) { item in
                            VStack {
                                PlayableArtworkView(item: item)
                                Text(item.title)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .lineLimit(2, reservesSpace: true)
                                    .fontDesign(.rounded)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .containerRelativeFrame(
                                .horizontal, alignment: .topLeading
                            ) { length, axis in
                                if axis == .vertical {
                                    return length / 3.0
                                } else {
                                    return length / 2.5
                                }
                            }
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
                    HStack(spacing: 2) {
                        Text("Albums")
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
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
                .listRowSeparator(.hidden)
        }
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}
