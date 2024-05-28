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
    @Environment(SonosService.self) private var sonosService
    @Environment(MusicSearchService.self) var musicSearchService
    @State private var router = Router()

    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    @State private var betaFeatures = BetaFeatures()
    @State private var alertService = AlertService()

    @CloudStorage(CloudKeys.playHistory) private var playHistory: OrderedSet<PlayableContent> = [] {
        didSet {
            playHistory = OrderedSet(playHistory.prefix(15))
        }
    }
    var group: GroupRoom? = nil

    @State private var playlists: [PlayableContent] = []

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                ForEach(playlists) { item in
                    VStack {
                        PlayableContentView(item: item, group: group)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    Task {
                                        await sonosService.delete(playlistID: item.id)
                                        playlists.removeAll { $0.id == item.id }
                                    }
                                }
                            }
                    }
                }
            }
            .animation(.bouncy, value: playlists)
            .fontDesign(.rounded)
            .task {
                playlists = await sonosService.sonosPlaylists()
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
                playlists = await sonosService.sonosPlaylists()
            }
        }
    }
}

#Preview {
    BrowseScreen()
        .withEnvironments()
}

