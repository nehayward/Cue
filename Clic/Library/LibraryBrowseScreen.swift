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
    @Environment(\.dismiss) var dismiss

    @Environment(SonosService.self) private var sonosService
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(LibraryBrowseService.self) var browseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    @State private var router = Router()
    @State private var alertService = AlertService()

    var body: some View {
        @Bindable var sonosService = sonosService
        @Bindable var browseService = browseService

        NavigationStack(path: $router.path) {
            List {
                NavigationLink(value: RouterDestination.playableContentList(group: selectedGroupService.group, contentType: .artist)) {
                    Label("Artists", systemImage: "music.mic")
                }
                .listRowSeparator(.hidden, edges: .top)

                NavigationLink(value: RouterDestination.playableContentList(group: selectedGroupService.group, contentType: .album)) {
                    Label("Albums", systemImage: "smallcircle.circle.fill")
                }

                NavigationLink(value: RouterDestination.playableContentList(group: selectedGroupService.group, contentType: .track)) {
                    Label("Songs", systemImage: "music.note")
                }
                
//                NavigationLink(value: RouterDestination.playableLibraryList(title: "Genres", items: $browseService.genres, action: { offset in
//                    await browseService.updateGenres()
//                })) {
//                    Label("Genres", systemImage: "theatermasks.fill")
//                }

                NavigationLink(value: RouterDestination.playableLibraryList(title: "Imported Playlists", items: $browseService.importedPlaylists, action: { offset in
                    await browseService.updateImportedPlaylists()
                })) {
                    Label("Imported Playlists", systemImage: "rectangle.stack.badge.play")
                }

//                NavigationLink(value: RouterDestination.playableContentList(group: selectedGroupService.group, contentType: .playlist)) {
//                    Label("Playlists", systemImage: "rectangle.stack.badge.play")
//                }

//                if !browseService.playlists.isEmpty {
//                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
//                        ForEach(browseService.playlists.prefix(5)) { item in
//                            PlayableCardView(item: item)
//                        }
//                    }
//                }

                NavigationLink(value: RouterDestination.playableContentList(group: selectedGroupService.group, contentType: .playlist)) {
                    Label("Saved Playlists", systemImage: "rectangle.stack.badge.play")
                }
                if !browseService.playlists.isEmpty {
                    ForEach(browseService.playlists.prefix(5)) { item in
                        PlayableContentView(item: item)
                    }
                }
            }
//            .foregroundStyle(.primary)
            .miniPlayerOnScrollHandler()
            .listStyle(.inset)
            .navigationTitle("Music Library")
            .navigationBarTitleDisplayMode(.inline)
            .fontDesign(.rounded)
            .task {
                await browseService.updatePlaylists()
            }
            .withAppRouter()
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await browseService.updatePlaylists()
            }
        }
    }
}

#Preview {
    LibraryBrowseScreen()
        .withEnvironments()
}

