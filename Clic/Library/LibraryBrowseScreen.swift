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

struct LibraryBrowseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(BrowseService.self) var browseService

    @State private var router = Router()
    @State private var alertService = AlertService()

    var group: GroupRoom? = nil

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                NavigationLink(value: RouterDestination.playableContentList(group: group, contentType: .artist)) {
                    Label("Artists", systemImage: "music.mic")
                }

                NavigationLink(value: RouterDestination.playableContentList(group: group, contentType: .album)) {
                    Label("Albums", systemImage: "circle.circle.fill")
                }

                NavigationLink(value: RouterDestination.playableContentList(group: group, contentType: .track)) {
                    Label("Songs", systemImage: "music.note")
                }

                NavigationLink(value: RouterDestination.playableContentList(group: group, contentType: .playlist)) {
                    Label("Playlists", systemImage: "list.bullet")
                }
            }
            .withAppRouter(router: router)
            .listStyle(.inset)
            .navigationTitle("Music Library")
            .fontDesign(.rounded)
        }
        .environment(router)
        .tabItem {
            Text("Music Library")
        }
    }
}

#Preview {
    LibraryBrowseScreen()
        .withEnvironments()
}

