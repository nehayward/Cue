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

struct GenreListView: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(MusicSearchService.self) var musicSearchService
    @Environment(LibraryBrowseService.self) var browseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    @State private var alertService = AlertService()

    var body: some View {
        List {
            ForEach(browseService.genres) { genre in
                NavigationLink(value: RouterDestination.playableList(title: genre.title, action: { offset in
                    await sonosService.libraryLookup(ID: genre.id)
                })) {
                    Text(genre.title)
                }
            }
        }
        .miniPlayerOnScrollHandler()
        .listStyle(.inset)
        .navigationTitle("Genres")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .task {
            await browseService.updateGenres()
        }
    }
}

#Preview {
    LibraryBrowseScreen()
        .withEnvironments()
}

