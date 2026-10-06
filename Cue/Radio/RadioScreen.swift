import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The Radio tab: stations that play on this device as well as on a
/// speaker. That rule picks the sources — TuneIn (the stations near the
/// user, what's trending, and the rest of its directory) and Apple Music's
/// live and personal stations — each only while its provider is switched
/// on in Services. Sonos Radio and Sonos favorites are speaker-only, so
/// they stay on Browse and Search. Typing in the field searches the same
/// sources for stations by name.
struct RadioScreen: View {
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(AppleMusicBrowseService.self) private var appleMusicBrowseService
    @Environment(TuneInBrowseService.self) private var tuneInBrowseService
    @Environment(CoreFeatures.self) private var coreFeatures
    @Environment(\.horizontalSizeClass) private var sizeClass

    @AppStorage(AppStorageKeys.appleMusicAuthorized) private var appleMusicAuthorized: AppleMusicAuthorization = .notDetermined

    /// This tab's own stack, never a shared router: two stacks bound to one
    /// path push each other.
    @State private var router = Router()
    @State private var query = ""
    @State private var search = RadioSearch()

    private var showsTuneIn: Bool { coreFeatures.isEnabled(.tuneIn) }
    /// Apple's stations load on open, so they wait for an authorization the
    /// user has already given rather than prompting for one from this tab.
    /// Search still asks, the way the Search tab does.
    private var showsApple: Bool { coreFeatures.isEnabled(.apple) && appleMusicAuthorized == .authorized }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSource: Bool {
        showsTuneIn || showsApple
    }

    private var isEmpty: Bool {
        tuneInBrowseService.localStations.isEmpty
            && tuneInBrowseService.trending.isEmpty
            && appleMusicBrowseService.radioStations.isEmpty
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

    /// Apple's covers first, the tab's most recognisable stations; then
    /// TuneIn's rows, ending on its directory, the way into everything else.
    @ViewBuilder
    private var browseSections: some View {
        if showsApple {
            appleSections
        }
        if showsTuneIn {
            tuneInSections
        }
        if tuneInBrowseService.isLoading, isEmpty {
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
                seeAll: .playableList(
                    title: "Local Radio",
                    showSectionIndex: false,
                    searchAction: { query, offset in offset == 0 ? Self.filter(local, by: query) : [] },
                    action: { offset in offset == 0 ? local : [] }
                )
            )
        }
        if !trending.isEmpty {
            RadioStationsSection(
                title: "Trending",
                caption: "TuneIn",
                items: trending,
                seeAll: .playableList(
                    title: "Trending",
                    showSectionIndex: false,
                    searchAction: { query, offset in offset == 0 ? Self.filter(trending, by: query) : [] },
                    action: { offset in offset == 0 ? trending : [] }
                )
            )
        }
        if let error = tuneInBrowseService.error {
            notice(error)
        }

        Section {
            RadioSectionHeader(title: "Browse", caption: "TuneIn")

            LazyVGrid(columns: RadioGrid.columns(sizeClass == .compact ? 2 : 4), spacing: RadioGrid.spacing) {
                // Plain buttons, as the station rows are: several links in
                // one list row each take their own tap only when styled.
                ForEach(TuneInDirectoryPage.allCases) { page in
                    Button {
                        router.navigate(to: .tuneInBrowse(title: page.title, url: page.page.url))
                    } label: {
                        TuneInDirectoryTile(page: page)
                    }
                    .buttonStyle(.plain)
                }
            }
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
                items: stations,
                seeAll: .playableList(title: "Apple Music Radio", showSectionIndex: false, action: { offset in offset == 0 ? stations : [] }),
                style: .artwork
            )
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
                Text("Switch on TuneIn or Apple Music in Settings › Services to browse stations here.")
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

    /// The stations whose name matches the query. TuneIn puts the
    /// frequency, call sign and genre in the title ("88.5 | KNKX (Jazz)"),
    /// so matching on it covers all three.
    private static func filter(_ stations: [PlayableContent], by query: String) -> [PlayableContent] {
        stations.filter { station in
            [station.title, station.subtitle].contains { $0.localizedCaseInsensitiveContains(query) }
        }
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

    /// Both sources at once. A refresh drops TuneIn's cache so it fetches
    /// again; the first load lets it paint what it has.
    private func load(refreshing: Bool) async {
        await withTaskGroup(of: Void.self) { group in
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
        }
    }
}

/// One of the top pages of TuneIn's directory, as a tile the same height
/// as the station rows above it.
private struct TuneInDirectoryTile: View {
    let page: TuneInDirectoryPage

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: page.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                // One width for every symbol, so the names line up.
                .frame(width: 30)
            Text(page.title)
                .fontWeight(.medium)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
        .background(.fill.tertiary, in: .rect(cornerRadius: RadioGrid.cornerRadius))
        .contentShape(.rect(cornerRadius: RadioGrid.cornerRadius))
    }
}

/// The top of TuneIn's directory, as the tiles under "Browse".
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
