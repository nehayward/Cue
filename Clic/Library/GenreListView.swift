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
    @State private var isLoadingMore = false
    @State private var hasMoreGenres = true

    var body: some View {
        List {
            ForEach(browseService.genres) { genre in
                NavigationLink(value: RouterDestination.playableList(title: genre.title, action: { offset in
                    await sonosService.libraryLookup(ID: genre.id, offset: offset)
                })) {
                    Text(genre.title)
                }
                .task {
                    await loadMoreIfNeeded(currentGenre: genre)
                }
            }
        }
        .miniPlayerOnScrollHandler()
        .listStyle(.inset)
        .navigationTitle("Genres")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .task {
            hasMoreGenres = await browseService.updateGenres()
        }
    }

    /// Loads the next page of genres as the user nears the end, guarded so it
    /// doesn't re-fire redundant requests once the list is exhausted.
    private func loadMoreIfNeeded(currentGenre: PlayableContent) async {
        guard !isLoadingMore, hasMoreGenres,
              (browseService.genres.firstIndex(of: currentGenre) ?? 0) >= browseService.genres.count / 2
        else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        hasMoreGenres = await browseService.updateGenres(offset: browseService.genres.count)
    }
}

#Preview {
    LibraryBrowseScreen()
        .withEnvironments()
}

