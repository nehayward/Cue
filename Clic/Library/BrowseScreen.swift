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

struct BrowseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SelectedGroupService.self) private var selectedGroupService

    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    @State private var browseService = BrowseService.shared
    @State private var router = Router()
    @State private var alertService = AlertService()
    @State private var isLoaded: Bool = false

    var body: some View {
//        TabView {
//            LibraryBrowseScreen(group: group)
//                .environment(browseService)

//            ApplePlaylistsScreen(group: group)
            NavigationStack(path: $router.path) {
                List {
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
                }
                .animation(.bouncy, value: browseService.playlists)
                .task {
                    isLoaded = false
                    await browseService.updatePlaylists()
                    isLoaded = true
                }
                .withAppRouter(router: router)
                .listStyle(.plain)
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            router.presentedSheet = .newPlaylist()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .addDismiss(override: UIDevice.current.userInterfaceIdiom == .mac, action: dismiss.callAsFunction)
                .overlay {
                    if browseService.playlists.isEmpty, isLoaded {
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
                .contentMargins(.bottom, 80, for: .scrollContent)
            }
            .environment(router)
            .environment(selectedGroupService)
            .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
                Task {
                    await browseService.updatePlaylists()
                }
            }
            .safeAreaInset(edge: .bottom) {
                MiniPlayerView()
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
//        }
    }

}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

