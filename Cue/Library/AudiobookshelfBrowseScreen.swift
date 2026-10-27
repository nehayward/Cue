import MusicSearchKit
import SonosKit
import SwiftUI

/// The listener's Audiobookshelf books: what they're partway through, the
/// chosen library's books, and what was added lately. Laid out like the
/// Apple and Plex libraries: one group of rows, then the shelves.
struct AudiobookshelfBrowseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService

    @State private var router = Router.browse
    @State private var browse = AudiobookshelfBrowseService.shared
    @State private var hasLoadedOnce = false

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                if browse.isAuthenticated {
                    if browse.libraries.count > 1 {
                        libraryPicker
                    }

                    if let library = browse.selectedLibrary {
                        NavigationLink(value: RouterDestination.playableList(
                            title: library.name,
                            showSectionIndex: false,
                            allowsGrid: true,
                            sortOptions: sortOptions,
                            sortKey: "audiobookshelf.books",
                            // A pull has the server scan for books added on it.
                            refreshAction: { await browse.scanAndRefresh() },
                            searchAction: { query, offset in
                                // The server answers a search in one go.
                                guard offset == 0 else { return [] }
                                return await browse.search(query)
                            },
                            loadingStatus: { browse.isScanning ? "Scanning…" : nil }
                        )) {
                            Label("All Books", systemImage: "books.vertical")
                        }
                    }

                    if !browse.podcastLibraries.isEmpty {
                        NavigationLink(value: RouterDestination.audiobookshelfPodcasts) {
                            Label("Podcasts", systemImage: "mic")
                        }
                    }

                    if browse.isLoading, browse.libraries.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    if !browse.continueListening.isEmpty {
                        Section {
                            ForEach(browse.continueListening) { book in
                                AudiobookRow(book: book)
                            }
                        } header: {
                            Text("Continue Listening")
                        }
                    }

                    // A podcast library's newest episodes, each playing as a
                    // book of one file.
                    if !browse.latestEpisodes.isEmpty {
                        Section {
                            ForEach(browse.latestEpisodes.prefix(Self.latestEpisodeRows)) { episode in
                                AudiobookRow(book: episode)
                            }
                        } header: {
                            Text("Latest Episodes")
                        }
                    }

                    if browse.selectedLibrary != nil {
                        // As the Apple library shows it: the title opens every
                        // book by when it was added, the newest under it out
                        // of the group.
                        Section {
                            NavigationLink(value: recentlyAddedDestination) {
                                Text("Recently Added")
                                    .fontDesign(.rounded)
                                    .fontWeight(.semibold)
                            }

                            PlayableContentGridView(items: browse.recentlyAdded, limit: 6)
                        }
                        .listSectionSpacing(0)
                        .listRowInsets(.default)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .overlay {
                if !browse.isAuthenticated {
                    notConnectedView
                } else if browse.failed, browse.libraries.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't Reach Audiobookshelf", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check that the server is running and reachable from here, then pull to refresh.")
                    }
                }
            }
            .animation(hasLoadedOnce ? .default : nil, value: browse.continueListening)
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
            .miniPlayerOnScrollHandler()
            // Default placement, as on Plex's: `.scrollContent` insets the
            // rows but leaves the group's background running to the edge.
            .contentMargins(.horizontal, 16)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Audiobookshelf")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await browse.load()
                hasLoadedOnce = true
            }
            .refreshable {
                await browse.scanAndRefresh()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarButton()
                        .environment(router)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    MediaSelector()
                        .environment(router)
                }
            }
#if !targetEnvironment(macCatalyst)
            .addDismiss {
                dismiss()
                Router.main.inspectorSheet = nil
            }
#endif
            .withAppRouter()
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task { await browse.load() }
        }
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }

    private static let latestEpisodeRows = 5

    /// Several libraries: the shelves are one's at a time.
    private var libraryPicker: some View {
        Menu {
            ForEach(browse.libraries) { library in
                Button {
                    browse.select(library)
                } label: {
                    if library.id == browse.selectedLibrary?.id {
                        Label(library.name, systemImage: "checkmark")
                    } else {
                        Text(library.name)
                    }
                }
            }
        } label: {
            Label(browse.selectedLibrary?.name ?? "Library", systemImage: "books.vertical.fill")
        }
    }

    /// Every book in the library by when it was added, newest first.
    private var recentlyAddedDestination: RouterDestination {
        .playableList(
            title: "Recently Added",
            showSectionIndex: false,
            allowsGrid: true,
            action: { offset in
                await browse.books(offset: offset, sort: "addedAt", descending: true)
            }
        )
    }

    private var sortOptions: [PlayableListSort] {
        browse.bookSortOptions
    }

    private var notConnectedView: some View {
        ContentUnavailableView {
            Label("Audiobookshelf Isn't Set Up", systemImage: MusicService.audiobookshelfSymbolName)
        } description: {
            Text("Sign in to your Audiobookshelf server to listen to your books here or on your speakers, and keep your place in step with its other apps.")
        } actions: {
            VStack(spacing: 20) {
                Button {
                    router.presentedSheet = .audiobookshelfManagement
                } label: {
                    Text("Sign In")
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)

                Link(destination: URL(string: "https://www.audiobookshelf.org")!) {
                    HStack(spacing: 4) {
                        Text("About Audiobookshelf")
                        Image(systemName: "arrow.up.forward")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.accent)
            }
        }
    }
}
