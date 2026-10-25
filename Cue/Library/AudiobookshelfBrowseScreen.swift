import MusicSearchKit
import SonosKit
import SwiftUI

/// The listener's Audiobookshelf books: what they're partway through, the
/// chosen library's books, and what was added lately. Laid out like the
/// Subsonic screen beside it.
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
                            .listRowInsets(.default)
                            .listRowSeparator(.hidden)
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
                        .listRowInsets(.default)
                        .listRowSeparator(.hidden)
                    }

                    if !browse.continueListening.isEmpty {
                        Section {
                            Text("Continue Listening")
                                .fontDesign(.rounded)
                                .fontWeight(.semibold)
                            ForEach(browse.continueListening) { book in
                                AudiobookRow(book: book)
                            }
                        }
                        .listRowInsets(.default)
                        .listRowSeparator(.hidden)
                        .listSectionSeparator(.hidden)
                    }

                    if !browse.recentlyAdded.isEmpty {
                        Section {
                            Text("Recently Added")
                                .fontDesign(.rounded)
                                .fontWeight(.semibold)

                            LazyVGrid(columns: [.init(), .init()]) {
                                ForEach(browse.recentlyAdded) { item in
                                    PlayableContentRowView(item: item)
                                        .buttonStyle(.plain)
                                        .geometryGroup()
                                }
                            }
                        }
                        .listRowInsets(.default)
                        .listRowSeparator(.hidden)
                        .listSectionSeparator(.hidden)
                    }

                    if browse.isLoading, browse.libraries.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
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
            .listSectionSpacing(4)
            .listStyle(.plain)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .animation(hasLoadedOnce ? .default : nil, value: browse.continueListening)
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
            .miniPlayerOnScrollHandler()
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
