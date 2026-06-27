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
    @State private var hasMoreContent: Bool = true
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
            tracksList
        case .album:
            albumSections
        case .artist:
            artistSections
        case .playlist:
            playlistSections
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var tracksList: some View {
        ForEach(browseService.songs) { item in
            VStack {
                PlayableContentView(item: item)
            }
        }
    }

    @ViewBuilder
    private var albumSections: some View {
        ForEach(browseService.albumSections) { section in
            Section(header: Text(section.letter)) {
                ForEach(section.items) { item in
                    VStack {
                        PlayableContentView(item: item)
                    }
                }
            }
            .sectionIndex(section.letter)
        }
    }

    @ViewBuilder
    private var artistSections: some View {
        ForEach(browseService.artistSections) { section in
            Section(header: Text(section.letter)) {
                ForEach(section.items) { item in
                    VStack {
                        PlayableContentView(item: item)
                    }
                }
            }
            .sectionIndex(section.letter)
        }
    }

    @ViewBuilder
    private var playlistSections: some View {
        ForEach(browseService.playlistSections) { section in
            Section(header: Text(section.letter)) {
                ForEach(section.items) { item in
                    VStack {
                        PlayableContentView(item: item)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            Task {
                                await sonosService.delete(playlistID: item.id)
                                browseService.removePlaylist(id: item.id)
                            }
                        }
                    }
                }
            }
            .sectionIndex(section.letter)
        }
    }
    
    @ViewBuilder
    private var loadMoreIndicator: some View {
        if hasMoreContent {
            // A near-invisible row keeps the paging trigger alive; the spinner
            // only appears while a next page is actually being fetched (not on
            // the initial load, which has its own full-screen overlay).
            VStack {
                if isLoading && !isCurrentListEmpty {
                    ProgressView()
                        .padding(.vertical, 8)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .onAppear { Task { await loadMoreContent() } }
        }
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        // Only the initial load shows the full-screen spinner; paging more
        // pages happens silently in the background.
        if isLoading && isCurrentListEmpty {
            ProgressView()
                .padding()
                .background(.thickMaterial)
        }
    }

    private var isCurrentListEmpty: Bool {
        switch type {
        case .track:
            return browseService.songs.isEmpty
        case .album:
            return browseService.albums.isEmpty
        case .artist:
            return browseService.artists.isEmpty
        case .playlist:
            return browseService.playlists.isEmpty
        default:
            return true
        }
    }
    
    private var playlistToolbarItems: some ToolbarContent {
        Group {
            if type == .playlist {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        router.presentedSheet = .newPlaylist()
                    } label: {
                        Label("Add", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var emptyPlaylistView: some View {
        if !isLoading {
            switch type {
            case .playlist where browseService.playlists.isEmpty:
                ContentUnavailableView {
                    Label("No Playlists", systemImage: "music.note.list")
                } description: {
                    Text("Create playlists to organize your favorite music")
                } actions: {
                    Button {
                        router.presentedSheet = .newPlaylist()
                    } label: {
                        Text("Create Playlist")
                    }
                    .buttonStyle(.bordered)
                    .tint(.accent)
                    .padding()
                }
            case .track where browseService.songs.isEmpty:
                ContentUnavailableView {
                    Label("No Tracks", systemImage: "music.note")
                } description: {
                    Text("Your library doesn't contain any tracks")
                }
            case .album where browseService.albums.isEmpty:
                ContentUnavailableView {
                    Label("No Albums", systemImage: "square.stack")
                } description: {
                    Text("Your library doesn't contain any albums")
                }
            case .artist where browseService.artists.isEmpty:
                ContentUnavailableView {
                    Label("No Artists", systemImage: "music.mic")
                } description: {
                    Text("Your library doesn't contain any artists")
                }
            default:
                EmptyView()
            }
        }
    }
    
    private func loadInitialContent() async {
        isLoading = true
        defer { isLoading = false }

        switch type {
        case .track:
            hasMoreContent = await browseService.updateSongs()
        case .album:
            hasMoreContent = await browseService.updateAlbum()
        case .artist:
            hasMoreContent = await browseService.updateArtists()
        case .playlist:
            await browseService.updatePlaylists()
            hasMoreContent = false
        default:
            hasMoreContent = false
        }
    }

    private func loadMoreContent() async {
        guard !isLoading, hasMoreContent else { return }
        isLoading = true
        defer { isLoading = false }

        switch type {
        case .track:
            hasMoreContent = await browseService.updateSongs(offset: browseService.songs.count)
        case .album:
            hasMoreContent = await browseService.updateAlbum(offset: browseService.albums.count)
        case .artist:
            hasMoreContent = await browseService.updateArtists(offset: browseService.artists.count)
        default:
            hasMoreContent = false
        }
    }
}
