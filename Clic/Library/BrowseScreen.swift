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
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    @AppStorage(AppStorageKeys.browseMediaService) private var browseMediaService: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    @State private var router = Router()
    @State private var alertService = AlertService()
    @State private var isLoaded: Bool = false
    @State private var coreFeatures = CoreFeatures()

    var body: some View {
        Group {
            switch browseMediaService {
            case .apple:
                AppleLibraryBrowseScreen()
                // TODO: Next release
//            case .spotify:
////                SpotifyBrowseScreen()
            case .library:
                LibraryBrowseScreen()
            default:
                NavigationStack {
                    EmptyView()
                        .addDismiss(action: dismiss.callAsFunction)
                }
            }
        }
        .contentMargins(.bottom, 80, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            VStack {
                Menu {
                    ForEach(MediaSearchService.allCases, id: \.self) { service in
                        // MARK: Add Spotify
                        if coreFeatures.enabledServices(service).wrappedValue, [MediaSearchService.apple, MediaSearchService.library].contains(service) {
                            Button {
                                HapticManager.shared.fireHaptic(.buttonPress)
                                browseMediaService = service
                            } label: {
                                HStack {
                                    Text(service.title)
                                    service.image
                                }
                            }
                            .tag(service)
                        }
                    }
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        router.presentedSheet = .settings
                    } label: {
                        Text("Customize in Settings…")
                    }
                } label: {
                    browseMediaService.image
                        .frame(width: 24, height: 24)
                }
                .popoverTip(AppTip.mediaService)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding()

                MiniPlayerView()
            }
        }
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        //            NavigationStack(path: $router.path) {
        //                List {
        //                    ForEach(browseService.playlists) { item in
        //                        PlayableContentView(item: item)
        //                            .swipeActions(edge: .trailing) {
        //                                Button("Delete", role: .destructive) {
        //                                    Task {
        //                                        await sonosService.delete(playlistID: item.id)
        //                                        browseService.playlists.removeAll { $0.id == item.id }
        //                                    }
        //                                }
        //                            }
        //                    }
        //                }
        //                .animation(.bouncy, value: browseService.playlists)
        //                .task {
        //                    isLoaded = false
        //                    await browseService.updatePlaylists()
        //                    isLoaded = true
        //                }
        //                .withAppRouter(router: router)
        //                .listStyle(.plain)
        //                .navigationTitle("Library")
        //                .toolbar {
        //                    ToolbarItem(placement: .confirmationAction) {
        //                        Button {
        //                            router.presentedSheet = .newPlaylist()
        //                        } label: {
        //                            Image(systemName: "plus")
        //                        }
        //                    }
        //                }
        //                .addDismiss(override: UIDevice.current.userInterfaceIdiom == .mac, action: dismiss.callAsFunction)
        //                .overlay {
        //                    if browseService.playlists.isEmpty, isLoaded {
        //                        ContentUnavailableView {
        //                            Text("No Playlists")
        //                        } actions: {
        //                            Button {
        //                                router.presentedSheet = .newPlaylist()
        //                            } label: {
        //                                Text("Create a playlist to get started")
        //                            }
        //                            .buttonStyle(.bordered)
        //                            .tint(.accent)
        //                            .padding()
        //                        }
        //                    }
        //                }
        //                .fontDesign(.rounded)
        //                .contentMargins(.bottom, 80, for: .scrollContent)
        //            }
        //            .environment(router)
        //            .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
        //                Task {
        //                    await browseService.updatePlaylists()
        //                }
        //            }
    }


}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

