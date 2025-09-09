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

struct SpotifyLibraryScreen: View {
    @Environment(\.dismiss) var dismiss

    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SpotifyBrowseService.self) private var spotifyBrowseService

    @State private var router = Router()
    @State private var isLoading = true

    var body: some View {
        NavigationStack(path: $router.path) {
            ScrollView {
                LazyVStack {
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
                                                return length / 2.5
                                            }
                                        }
                                        .draggable(item)
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                            .scrollClipDisabled()
                            .padding(.bottom, 24)
                        } header: {
                            NavigationLink(value: RouterDestination.playableList(title: "Spotify Songs", action: { offset in
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
                                        .containerRelativeFrame(.horizontal, alignment: .topLeading
                                        ) { length, axis in
                                            if axis == .vertical {
                                                return length / 3.0
                                            } else {
                                                return length / 2.5
                                            }
                                        }
                                        .draggable(item)
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
                    }
                    
                    NavigationLink(value: RouterDestination.playableList(title: "Spotify Playlists", action: { offset in
                        await spotifyBrowseService.updatePlaylists(offset: offset)
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
                    if !spotifyBrowseService.playlists.isEmpty {
                        ForEach(spotifyBrowseService.playlists.prefix(10)) { item in
                            PlayableContentView(item: item)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .headerProminence(.increased)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Spotify Library")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await updateSpotifyBrowseService()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MediaSelector()
                        .environment(router)
                }
            }
#if !targetEnvironment(macCatalyst)
            .addDismiss {
                dismiss()
                Router.main.inspectorSheet = nil
            }
#endif
            .refreshable {
                spotifyBrowseService.playlists.removeAll()
                spotifyBrowseService.tracks.removeAll()
                spotifyBrowseService.albums.removeAll()
                await updateSpotifyBrowseService()
            }
            .withAppRouter()
        }
        .overlay {
            if isLoading, spotifyBrowseService.playlists.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task {
                await updateSpotifyBrowseService()
            }
        }
    }
    
    private func updateSpotifyBrowseService(offset: Int = 0) async {
        isLoading = true
        defer { isLoading = false }
        await spotifyBrowseService.updatePlaylistsAndSongs(offset: offset)
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}
