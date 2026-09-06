import MusicSearchKit
import SonosKit
import SwiftUI

/// A provider's tab, on iPad and Mac. With no `collection` it is the
/// provider's own tab — the library's front page, listing the collections
/// its sidebar section is showing, which is what the collapsed tab bar
/// opens. With one, it is that collection as a tab of its own: the tabs the
/// sidebar section holds. Both render the same destinations, so the row on
/// the front page and the sidebar tab open one screen.
struct ProviderTabScreen: View {
    let service: MediaSearchService
    /// The collections the front page lists, in order.
    let collections: [ProviderCollection]
    /// Nil for the front page.
    var collection: ProviderCollection? = nil

    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService
    @Environment(SpotifyBrowseService.self) private var spotifyBrowseService
    @Environment(SoundCloudBrowseService.self) private var soundCloudBrowseService
    @Environment(DeezerBrowseService.self) private var deezerBrowseService
    @Environment(SubsonicBrowseService.self) private var subsonicBrowseService
    @Environment(PlexBrowseService.self) private var plexBrowseService
    @Environment(LibraryBrowseService.self) private var libraryBrowseService
    @Environment(SelectedGroupService.self) private var selectedGroupService: SelectedGroupService?

    /// One router per tab, never `Router.browse`: the Browse tab may be
    /// showing this same provider, and two `NavigationStack`s bound to one
    /// path push and pop each other.
    @State private var router = Router()

    private var library: ProviderLibrary {
        ProviderLibrary(
            service: service,
            musicSearchService: musicSearchService,
            appleMusicBrowseService: appleMusicBrowseService,
            spotifyBrowseService: spotifyBrowseService,
            soundCloudBrowseService: soundCloudBrowseService,
            deezerBrowseService: deezerBrowseService,
            subsonicBrowseService: subsonicBrowseService,
            plexBrowseService: plexBrowseService,
            libraryBrowseService: libraryBrowseService,
            group: selectedGroupService?.group
        )
    }

    var body: some View {
        let library = library

        NavigationStack(path: $router.path) {
            Group {
                if !library.isReady {
                    notReady
                } else if let collection, let destination = library.destination(for: collection) {
                    RouterDestinationView(destination: destination)
                } else {
                    frontPage(library)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .fontDesign(.rounded)
            .withAppRouter()
            .toolbar {
                if let sheet = service.managementSheet {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            router.presentedSheet = sheet
                        } label: {
                            Label("Manage \(service.title)", systemImage: "server.rack")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
            }
            .task(id: library.isReady) {
                guard library.isReady else { return }
                await library.load()
            }
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            // A management sheet may have signed in or switched servers.
            Task { await library.load() }
        }
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }

    private func frontPage(_ library: ProviderLibrary) -> some View {
        List {
            ForEach(collections, id: \.self) { collection in
                if let destination = library.destination(for: collection) {
                    NavigationLink(value: destination) {
                        Label(collection.title, systemImage: collection.systemImage)
                    }
                }
            }
            if collections.isEmpty {
                Text("No collections showing. Switch some on with Edit in the sidebar.")
                    .foregroundStyle(.secondary)
            }
        }
        .contentMargins(.top, EdgeInsets(), for: .scrollContent)
        .contentMargins(.horizontal, 16)
        .miniPlayerOnScrollHandler()
        .navigationTitle(service.title)
    }

    @ViewBuilder
    private var notReady: some View {
        if service == .plex, musicSearchService.isPlexAuthorized {
            // Signed in but no server or library picked yet: the same rows
            // the library's front page shows to finish the setup.
            List {
                PlexLibrarySelectionView()
            }
            .contentMargins(.horizontal, 16)
            .navigationTitle(service.title)
        } else {
            ContentUnavailableView {
                Label("\(service.title) Isn't Set Up", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Sign in to \(service.title) to browse its library here.")
            } actions: {
                if let sheet = service.managementSheet {
                    Button {
                        router.presentedSheet = sheet
                    } label: {
                        Text("Set Up \(service.title)")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle(service.title)
        }
    }
}

#Preview {
    ProviderTabScreen(service: .plex, collections: MediaSearchService.plex.tabCollections, collection: .albums)
        .withEnvironments()
}
