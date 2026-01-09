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
        .tint(.primary)
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
        ForEach(groupedAlbums.keys.sorted(), id: \.self) { letter in
            Section(header: Text(letter)) {
                ForEach(groupedAlbums[letter] ?? []) { item in
                    VStack {
                        PlayableContentView(item: item)
                    }
                }
            }
            .sectionIndex(letter)
        }
    }

    @ViewBuilder
    private var artistSections: some View {
        ForEach(groupedArtists.keys.sorted(), id: \.self) { letter in
            Section(header: Text(letter)) {
                ForEach(groupedArtists[letter] ?? []) { item in
                    VStack {
                        PlayableContentView(item: item)
                    }
                }
            }
            .sectionIndex(letter)
        }
    }

    @ViewBuilder
    private var playlistSections: some View {
        ForEach(groupedPlaylists.keys.sorted(), id: \.self) { letter in
            Section(header: Text(letter)) {
                ForEach(groupedPlaylists[letter] ?? []) { item in
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
            .sectionIndex(letter)
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

    // MARK: - Alphabetical Grouping

    private var groupedAlbums: [String: [PlayableContent]] {
        Dictionary(grouping: browseService.albums) { item in
            guard let scalar = item.title
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .unicodeScalars
                .first,
                  CharacterSet.letters.contains(scalar)
            else { return "#" }
            
            return String(scalar).uppercased()
        }
    }

    private var groupedArtists: [String: [PlayableContent]] {
        Dictionary(grouping: browseService.artists) { item in
            guard let scalar = item.title
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .unicodeScalars
                .first,
                  CharacterSet.letters.contains(scalar)
            else { return "#" }
            
            return String(scalar).uppercased()
        }
    }

    private var groupedPlaylists: [String: [PlayableContent]] {
        Dictionary(grouping: browseService.playlists) { item in
            guard let scalar = item.title
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .unicodeScalars
                .first,
                  CharacterSet.letters.contains(scalar)
            else { return "#" }
            
            return String(scalar).uppercased()
        }
    }
}
