import CloudStorage
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import VibesDS

struct PlayableContentList: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(LibraryBrowseService.self) var browseService
    @Environment(Router.self) var router

    @State private var isLoading: Bool = false
    @State private var navigationTitle: String = ""
    
    var type: ContentType

    var body: some View {
        List {
            contentSection
            loadMoreIndicator
        }
        .foregroundStyle(.foreground)
        .listStyle(.plain)
        .task { await loadInitialContent() }
        .overlay { loadingOverlay }
        .animation(.bouncy, value: browseService.playlists)
        .toolbar { playlistToolbarItems }
        .overlay { emptyPlaylistView }
        .fontDesign(.rounded)
        .contentMargins(.bottom, 120, for: .scrollContent)
    }
    
    @ViewBuilder
    private var contentSection: some View {
        switch type {
        case .track:
            ForEach(browseService.songs) { item in
                VStack {
                    PlayableContentView(item: item)
                }
            }
        case .album:
            ForEach(browseService.albums) { item in
                VStack {
                    PlayableContentView(item: item)
                }
            }
        case .artist:
            ForEach(browseService.artists) { item in
                VStack {
                    PlayableContentView(item: item)
                }
            }
        case .playlist:
            ForEach(browseService.playlists) { item in
                VStack {
                    PlayableContentView(item: item)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) {
                        Task {
                            await sonosService.delete(playlistID: item.id)
                            browseService.playlists.removeAll { $0.id == item.id }
                        }
                    }
                }
            }
        default:
            EmptyView()
        }
    }
    
    private var loadMoreIndicator: some View {
        ProgressView()
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color.clear)
            .opacity(0.01)
            .task { await loadMoreContent() }
            .listRowSeparator(.hidden)
    }
    
    private var loadingOverlay: some View {
        Group {
            if isLoading {
                ProgressView()
                    .padding()
                    .background(.thickMaterial)
            }
        }
    }
    
    private var playlistToolbarItems: some ToolbarContent {
        Group {
            if type == .playlist {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        router.presentedSheet = .newPlaylist()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
    
    private var emptyPlaylistView: some View {
        Group {
            if browseService.playlists.isEmpty && !isLoading {
                ContentUnavailableView {
                    Text("No Playlists")
                } actions: {
                    Button {
                        router.presentedSheet = .newPlaylist()
                    } label: {
                        Text("Create a playlist to get started")
                    }
                    .buttonStyle(.bordered)
                    .tint(.accent)
                    .padding()
                }
            }
        }
    }
    
    private func loadInitialContent() async {
        isLoading = true
        defer { isLoading = false }
        
        switch type {
        case .track:
            await browseService.updateSongs()
        case .album:
            await browseService.updateAlbum()
        case .artist:
            await browseService.updateArtists()
        case .playlist:
            await browseService.updatePlaylists()
        default:
            break
        }
    }
    
    private func loadMoreContent() async {
        switch type {
        case .track:
            await browseService.updateSongs(offset: browseService.songs.count - 1)
        case .album:
            await browseService.updateAlbum(offset: browseService.albums.count - 1)
        case .artist:
            await browseService.updateArtists(offset: browseService.artists.count - 1)
        case .playlist:
            await browseService.updatePlaylists()
        default:
            break
        }
    }
}
