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
    @Environment(BrowseService.self) var browseService

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
                }
            default:
                EmptyView()
            }
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
    }
}
