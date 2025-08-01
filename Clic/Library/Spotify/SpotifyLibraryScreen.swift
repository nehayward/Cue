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
            List {
                if !spotifyBrowseService.tracks.isEmpty {
                    Section {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(spotifyBrowseService.tracks.prefix(10)) { item in
                                    PlayableArtworkView(item: item)
                                        .containerRelativeFrame(.horizontal, count: 4, spacing: 4)
                                        .listRowInsets(EdgeInsets())
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()
                    } header: {
                        NavigationLink(value: RouterDestination.playableList(title: "Spotify Songs", action: { offset in
                            await spotifyBrowseService.updateSongs()
                            return Array(spotifyBrowseService.tracks)
                        })) {
                            HStack {
                                Label("Songs", systemImage: "music.note")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listSectionSeparator(.hidden)
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
                            HStack {
                                Label("Albums", systemImage: "smallcircle.circle.fill")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .frame(maxWidth: .infinity)
                        }
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
                            HStack {
                                Label("Playlists", systemImage: "rectangle.stack.badge.play")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .headerProminence(.increased)
            .miniPlayerOnScrollHandler()
            .listStyle(.sidebar)
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
