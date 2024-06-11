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

struct ApplePlaylistsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(MusicSearchService.self) var musicSearchService

    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    @State private var router = Router()
    @State private var alertService = AlertService()
    @State private var playlists: [PlayableContent] = []
    @State private var applePlaylists: [PlayableContent] = []

    var group: GroupRoom? = nil

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                ForEach(playlists) { item in
                    VStack {
                        PlayableContentView(item: item, group: group)
//                            .swipeActions(edge: .trailing) {
//                                Button("Delete", role: .destructive) {
//                                    Task {
//                                        await sonosService.delete(playlistID: item.id)
//                                        playlists.removeAll { $0.id == item.id }
//                                    }
//                                }
//                            }
                    }
                }
            }
            .animation(.bouncy, value: playlists)
            .fontDesign(.rounded)
            .task {
                playlists = await musicSearchService.usersApplePlaylists()
            }
            .withAppRouter(router: router)
            .listStyle(.inset)
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
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task {
                playlists = await musicSearchService.usersApplePlaylists()
            }
        }
        .tabItem {
            Text("Apple")
        }
        .addDismiss(override: true) {
            dismiss()
        }
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

