import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The Radio tab: every station source in one place. Sonos favorites that
/// are stations; the stations near the user, what's trending, and the rest
/// of TuneIn's directory; Apple Music's live and personal stations; and
/// Sonos Radio's curated rows — each source only while its provider is
/// switched on in Services. Typing in the field searches the same sources
/// for stations by name.
struct RadioScreen: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService
    @Environment(SonosRadioBrowseService.self) private var sonosRadioBrowseService
    @Environment(TuneInBrowseService.self) private var tuneInBrowseService
    @Environment(CoreFeatures.self) private var coreFeatures

    @AppStorage(AppStorageKeys.browseMediaService) private var browseMediaService: MediaSearchService = .apple
    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    /// This tab's own stack, never `Router.browse`: Browse may be showing
    /// Sonos Radio, and two stacks bound to one path push each other.
    @State private var router = Router()
    @State private var query = ""
    @State private var search = RadioSearch()

    /// Sonos Radio rows shown here before the link to the whole thing —
    /// its browse screen lists every row, and this tab has other sources
    /// to fit.
    private let sonosRadioSectionLimit = 4

    private var showsTuneIn: Bool { coreFeatures.isEnabled(.tuneIn) }
    private var showsSonosRadio: Bool { coreFeatures.isEnabled(.sonosRadio) }
    /// Apple's stations load on open, so they wait for an authorization the
    /// user has already given rather than prompting for one from this tab.
    /// Search still asks, the way the Search tab does.
    private var showsApple: Bool { coreFeatures.isEnabled(.apple) && appleMusicAuthorized == .authorized }

    /// Sonos favorites that are stations, from any service.
    private var favoriteStations: [PlayableContent] {
        sonosService.favorites.filter { $0.content.type.isRadio || $0.metadata?.radioStation == true }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSource: Bool {
        showsTuneIn || showsApple || showsSonosRadio || !favoriteStations.isEmpty
    }

    private var isLoading: Bool {
        tuneInBrowseService.isLoading || sonosRadioBrowseService.isLoading
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                if !trimmedQuery.isEmpty {
                    searchSections
                } else if hasSource {
                    browseSections
                } else {
                    noSources
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(4)
            .headerProminence(.increased)
            .fontDesign(.rounded)
            .contentMargins(.top, EdgeInsets(), for: .scrollContent)
            .contentMargins(.bottom, 120, for: .scrollContent)
            .navigationTitle("Radio")
            .searchable(text: $query, prompt: "Stations")
            .task(id: trimmedQuery) {
                await search.run(
                    trimmedQuery,
                    tuneIn: showsTuneIn,
                    apple: coreFeatures.isEnabled(.apple),
                    sonosRadio: showsSonosRadio,
                    using: musicSearchService
                )
            }
            .task {
                await load(refreshing: false)
            }
            .refreshable {
                await load(refreshing: true)
            }
            .miniPlayerOnScrollHandler()
            .withAppRouter()
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }

    // MARK: - Browse

    @ViewBuilder
    private var browseSections: some View {
        let favorites = favoriteStations
        if !favorites.isEmpty {
            RadioStationsSection(
                title: "Your Stations",
                caption: "Sonos Favorites",
                items: favorites,
                seeAll: .playableList(title: "Your Stations", showSectionIndex: false, action: { offset in offset == 0 ? favorites : [] })
            )
        }
        if showsTuneIn {
            tuneInSections
        }
        if showsApple {
            appleSections
        }
        if showsSonosRadio {
            sonosRadioSections
        }
        if isLoading, favorites.isEmpty, tuneInBrowseService.localStations.isEmpty, tuneInBrowseService.trending.isEmpty, sonosRadioBrowseService.populatedSections.isEmpty {
            loadingRow
        }
    }

    @ViewBuilder
    private var tuneInSections: some View {
        let local = tuneInBrowseService.localStations
        let trending = tuneInBrowseService.trending

        if !local.isEmpty {
            RadioStationsSection(
                title: "Local Radio",
                caption: "TuneIn",
                items: local,
                seeAll: .playableList(title: "Local Radio", showSectionIndex: false, action: { offset in offset == 0 ? local : [] })
            )
        }
        if !trending.isEmpty {
            RadioStationsSection(
                title: "Trending",
                caption: "TuneIn",
                items: trending,
                seeAll: .playableList(title: "Trending", showSectionIndex: false, action: { offset in offset == 0 ? trending : [] })
            )
        }
        if let error = tuneInBrowseService.error {
            notice(error)
        }

        Section {
            ForEach(TuneInDirectoryPage.allCases) { page in
                NavigationLink(value: RouterDestination.tuneInBrowse(title: page.title, url: page.page.url)) {
                    Label(page.title, systemImage: page.systemImage)
                }
            }
        } header: {
            Text("Browse TuneIn")
        }
        .listRowInsets(.default)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private var appleSections: some View {
        let stations = appleMusicBrowseService.radioStations
        if !stations.isEmpty {
            RadioStationsSection(
                title: "Apple Music Radio",
                caption: "Apple Music",
                items: stations,
                seeAll: .playableList(title: "Apple Music Radio", showSectionIndex: false, action: { offset in offset == 0 ? stations : [] })
            )
        }
    }

    @ViewBuilder
    private var sonosRadioSections: some View {
        let sections = sonosRadioBrowseService.populatedSections

        ForEach(sections.prefix(sonosRadioSectionLimit)) { section in
            RadioStationsSection(
                title: section.title,
                caption: "Sonos Radio",
                items: section.items,
                seeAll: .playableList(title: section.title, showSectionIndex: false, action: { offset in
                    // Whole lists at once: an empty second page tells the
                    // list it has everything.
                    offset == 0 ? await sonosRadioBrowseService.allStations(for: section) : []
                })
            )
        }
        if let error = sonosRadioBrowseService.error, sections.isEmpty {
            notice(error)
        }
        if sections.count > sonosRadioSectionLimit {
            Section {
                Button {
                    // The rest lives on the Browse tab's Sonos Radio screen.
                    browseMediaService = .sonosRadio
                    Router.main.selectedTab = .browse
                } label: {
                    Label("All of Sonos Radio", systemImage: "dot.radiowaves.left.and.right")
                }
                .tint(.primary)
            }
            .listRowInsets(.default)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
        }
    }

    // MARK: - Search

    @ViewBuilder
    private var searchSections: some View {
        if search.isEmpty {
            if search.isSearching {
                loadingRow
            } else {
                Section {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        } else {
            resultSection("TuneIn", search.tuneIn)
            resultSection("Apple Music", search.apple)
            resultSection("Sonos Radio", search.sonosRadio)
        }
    }

    @ViewBuilder
    private func resultSection(_ title: String, _ items: [PlayableContent]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    PlayableContentView(item: item)
                }
            } header: {
                Text(title)
            }
        }
    }

    // MARK: - States

    private var loadingRow: some View {
        Section {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var noSources: some View {
        Section {
            ContentUnavailableView {
                Label("No Radio Sources", systemImage: "radio")
            } description: {
                Text("Switch on TuneIn, Apple Music or Sonos Radio in Settings › Services to browse stations here.")
            } actions: {
                Button {
                    router.presentedSheet = .settings(destination: .servicePreferenceScreen)
                } label: {
                    Text("Open Services")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    /// A refresh failed but the rows on screen are still good: say so
    /// under them rather than replacing them.
    private func notice(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "wifi.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: - Loading

    /// Every enabled source at once. A refresh drops each source's cache
    /// so it fetches again; the first load lets each paint what it has.
    private func load(refreshing: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await sonosService.getFavoriteList()
            }
            if showsTuneIn {
                group.addTask {
                    if refreshing {
                        await tuneInBrowseService.refresh()
                    } else {
                        await tuneInBrowseService.load()
                    }
                }
            }
            if showsApple {
                group.addTask {
                    await appleMusicBrowseService.updateLiveRadioStations()
                    await appleMusicBrowseService.updateRadioStations(offset: 0)
                }
            }
            if showsSonosRadio {
                group.addTask {
                    if refreshing {
                        await sonosRadioBrowseService.refresh()
                    } else {
                        await sonosRadioBrowseService.load()
                    }
                }
            }
        }
    }
}

/// The top of TuneIn's directory, as the rows under "Browse TuneIn".
private enum TuneInDirectoryPage: CaseIterable, Identifiable {
    case music
    case sports
    case talk
    case byLocation

    var id: Self { self }

    var title: String {
        switch self {
        case .music: "Music"
        case .sports: "Sports"
        case .talk: "Talk & News"
        case .byLocation: "By Location"
        }
    }

    var systemImage: String {
        switch self {
        case .music: "music.note"
        case .sports: "sportscourt"
        case .talk: "mic"
        case .byLocation: "globe"
        }
    }

    var page: TuneInBrowsePage {
        switch self {
        case .music: .music
        case .sports: .sports
        case .talk: .talk
        case .byLocation: .byLocation
        }
    }
}

#Preview {
    RadioScreen()
        .withEnvironments()
}
