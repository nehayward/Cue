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
    @State private var isLoadingMore: Bool = false
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
        ForEach(groupedAlbums, id: \.letter) { section in
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
        ForEach(groupedArtists, id: \.letter) { section in
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
        ForEach(groupedPlaylists, id: \.letter) { section in
            Section(header: Text(section.letter)) {
                ForEach(section.items) { item in
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
            }
            .sectionIndex(section.letter)
        }
    }
    
    @ViewBuilder
    private var loadMoreIndicator: some View {
        if hasMoreContent {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .onAppear { Task { await loadMoreContent() } }
        }
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
        guard !isLoading, !isLoadingMore, hasMoreContent else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

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

    // MARK: - Alphabetical Grouping

    private var groupedAlbums: [(letter: String, items: [PlayableContent])] {
        sectioned(browseService.albums)
    }

    private var groupedArtists: [(letter: String, items: [PlayableContent])] {
        sectioned(browseService.artists)
    }

    private var groupedPlaylists: [(letter: String, items: [PlayableContent])] {
        sectioned(browseService.playlists)
    }

    /// Groups items into alphabetical sections sorted by leading letter.
    /// Computes the grouping a single time so section views don't re-run it
    /// once per letter (previously O(letters × items) per render).
    private func sectioned<S: Sequence>(_ items: S) -> [(letter: String, items: [PlayableContent])] where S.Element == PlayableContent {
        let groups = Dictionary(grouping: items) { item -> String in
            guard let scalar = item.title
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .unicodeScalars
                .first,
                  CharacterSet.letters.contains(scalar)
            else { return "#" }

            return String(scalar).uppercased()
        }

        return groups.keys.sorted().map { (letter: $0, items: groups[$0] ?? []) }
    }
}
