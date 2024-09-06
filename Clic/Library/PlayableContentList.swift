import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import MusicSearchKit
import MusicKit
import NukeUI
import VibesDS

struct PlayableContentList: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(LibraryBrowseService.self) var browseService
    @Environment(Router.self) var router

    @State var isLoading: Bool = false
    @State var navigationTitle: String = ""
    
    var type: ContentType

    var body: some View {
        List {
            switch type {
            case .track:
                ForEach(browseService.songs) { item in
                    PlayableContentView(item: item)
                    
                }
            case .album:
                ForEach(browseService.albums) { item in
                    PlayableContentView(item: item)
                }
            case .artist:
                ForEach(browseService.artists) { item in
                    PlayableContentView(item: item)
                }
            case .playlist:
                ForEach(browseService.playlists) { item in
                    PlayableContentView(item: item)
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

            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .opacity(0.01)
                .task {
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
                .listRowSeparator(.hidden)
        }
        .foregroundStyle(.foreground)
        .listStyle(.plain)
        .task {
            isLoading = true
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
            isLoading = false
        }
        .overlay {
            if isLoading {
                ProgressView()
                    .padding()
                    .background(.thickMaterial)
            }
        }
        .animation(.bouncy, value: browseService.playlists)
        .toolbar {
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
        .overlay {
            if browseService.playlists.isEmpty, !isLoading {
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
        .fontDesign(.rounded)
        .contentMargins(.bottom, 120, for: .scrollContent)
    }
}
