#if os(iOS) && !targetEnvironment(macCatalyst)
import CarPlay
import MusicKit
import MusicSearchKit
import SonosKit

/// What the car's screen lists, read from the same services the phone's
/// screens use. Only what this device can play is listed — the car plays
/// through the phone, so a container is offered when the local queue can
/// expand it and a row when the local queue can take it.
@MainActor
enum CarPlayLibrary {
    /// A row that opens a list: the downloads by album, artist or song. Its
    /// list is loaded when the row is opened.
    struct Listing {
        let title: String
        let systemImage: String
        /// A count or other note under the title.
        var detail: String? = nil
        /// Everything the collection stands for, behind Shuffle above its
        /// list. Only the downloads' songs have one.
        var shuffleAll: PlayableContent? = nil
        /// Whether a song picked in the list plays the list from there on,
        /// as a song picked in an album does. Off for lists of albums and
        /// playlists, whose rows open rather than play.
        var playsInOrder = false
        let load: @MainActor () async -> [PlayableContent]
    }

    /// A provider's part of a list on the Library tab: its name, and what it
    /// has there that this device can play.
    struct Shelf {
        let title: String
        let items: [PlayableContent]
    }

    /// A titled run of stations on the Radio tab.
    struct StationSection {
        let title: String
        let stations: [PlayableContent]
    }

    /// The longest list loaded for the car. A car shows no more than
    /// `CPListTemplate.maximumItemCount`, and most cap a list far shorter
    /// while driving; past a couple of hundred rows nobody scrolls anyway.
    static var rowLimit: Int {
        min(CPListTemplate.maximumItemCount, 200)
    }

    /// The Recently Added lists: the newest is what's wanted in a car.
    private static let recentLimit = 50

    /// The newest albums at the foot of the Downloads tab.
    private static let recentDownloadsLimit = 12

    // MARK: - Recents

    /// What was last played in Cue, newest first — the phone's Recently
    /// Played — narrowed to what this device can play. Without Play All
    /// over the downloads (On This Device, Downloaded • a provider), which
    /// is a way to play rather than an album to go back to.
    static func recents() -> [PlayableContent] {
        let player = LocalPlaybackService.shared
        let history = Array(PlayHistoryService.shared.history)
        let playable = history.filter { player.canPlayAnywhereLocally($0) && !OnDeviceLibrary.isAllSongs($0) }
        return Array(playable.prefix(rowLimit))
    }

    // MARK: - Library

    /// The providers the Library tab browses: switched on and signed in, in
    /// the order the app lists them. None offline: no provider can answer
    /// without a network, and what's on this iPhone has the Downloads tab.
    static func libraryServices() -> [MediaSearchService] {
        guard !OfflineMode.shared.isActive else { return [] }
        return MediaSearchService.supported.filter(isReady)
    }

    /// The Library tab's sections, in order, that at least one of
    /// `services` can fill. Playlists first: the tab opens on them.
    static func librarySections(for services: [MediaSearchService]) -> [ProviderCollection] {
        [ProviderCollection.playlists, .recentlyAdded, .albums].filter { collection in
            services.contains { loader(collection, for: $0) != nil }
        }
    }

    /// `collection` from each of `services` that has it, loaded side by side
    /// and narrowed to what this device can play. A provider with nothing
    /// to show is left out.
    ///
    /// `arrived` gets the shelves so far, in the services' order, each time
    /// a provider answers with something: a server that's slow or out of
    /// reach (a home Plex server, away from home) holds up only its own
    /// shelf, not the whole list.
    @discardableResult
    static func shelves(
        _ collection: ProviderCollection,
        from services: [MediaSearchService],
        arrived: ([Shelf]) -> Void = { _ in }
    ) async -> [Shelf] {
        // Started outside the group, so a list given up on (the car gone,
        // the providers changed) doesn't cut a request off halfway: the
        // providers keep what they fetched for the next time.
        let loads = services.enumerated().compactMap { index, service -> (Int, Task<[PlayableContent], Never>)? in
            guard let load = loader(collection, for: service) else { return nil }
            return (index, Task { await load() })
        }
        let player = LocalPlaybackService.shared
        var found: [Int: Shelf] = [:]
        await withTaskGroup(of: (Int, [PlayableContent]).self) { group in
            for (index, load) in loads {
                group.addTask { (index, await load.value) }
            }
            for await (index, items) in group {
                let playable = items.filter { player.canPlayAnywhereLocally($0) }
                guard !playable.isEmpty, !Task.isCancelled else { continue }
                found[index] = Shelf(title: services[index].title, items: playable)
                arrived(found.keys.sorted().compactMap { found[$0] })
            }
        }
        return found.keys.sorted().compactMap { found[$0] }
    }

    /// Switched on in Services and set up far enough to browse. Apple Music
    /// waits for an authorization the user has already given: nothing on
    /// the car's screen should put up the phone's permission prompt.
    private static func isReady(_ service: MediaSearchService) -> Bool {
        guard CoreFeatures.shared.isEnabled(service) else { return false }
        let search = MusicSearchService.shared
        return switch service {
        case .apple: MusicAuthorization.currentStatus == .authorized
        case .plex: search.isPlexAuthorized && search.plexServerID != nil
        case .subsonic: search.isSubsonicConfigured
        case .files: FilesLibraryService.shared.isConfigured
        default: false
        }
    }

    /// Reads `collection` the way `service`'s own browse screen reads it;
    /// nil where the provider has no such collection.
    private static func loader(
        _ collection: ProviderCollection,
        for service: MediaSearchService
    ) -> (@MainActor () async -> [PlayableContent])? {
        switch (service, collection) {
        case (.apple, .playlists):
            return { await applePlaylists() }
        case (.apple, .recentlyAdded):
            let apple = AppleMusicBrowseService.shared
            return {
                await collect(limit: recentLimit) { offset in
                    await apple.libraryAlbums(offset: offset, sort: .recentlyAdded, descending: true)
                }
            }
        case (.apple, .albums):
            let apple = AppleMusicBrowseService.shared
            return {
                await collect { offset in
                    await apple.libraryAlbums(offset: offset, sort: .title)
                }
            }
        case (.plex, .playlists):
            let plex = PlexBrowseService.shared
            return {
                await plex.updateUserPlaylists()
                return Array(plex.userPlaylists)
            }
        case (.plex, .recentlyAdded):
            let plex = PlexBrowseService.shared
            return {
                await collect(limit: recentLimit) { offset in
                    await plex.updateUserAlbums(offset: offset, sort: .recentlyAdded)
                }
            }
        case (.plex, .albums):
            let plex = PlexBrowseService.shared
            return {
                await collect { offset in
                    await plex.updateUserAlbums(offset: offset, sort: .title)
                }
            }
        case (.subsonic, .playlists):
            let search = MusicSearchService.shared
            return { await search.subsonicUserPlaylists() }
        case (.subsonic, .recentlyAdded):
            let search = MusicSearchService.shared
            return {
                await collect(limit: recentLimit) { offset in
                    await search.subsonicAlbums(offset: offset, sort: .recentlyAdded)
                }
            }
        case (.subsonic, .albums):
            let search = MusicSearchService.shared
            return {
                await collect { offset in
                    await search.subsonicAlbums(offset: offset, sort: .title)
                }
            }
        case (.files, .playlists):
            let files = FilesLibraryService.shared
            return {
                await files.scanIfNeeded()
                return files.playlists
            }
        case (.files, .recentlyAdded):
            let files = FilesLibraryService.shared
            return {
                await files.scanIfNeeded()
                return files.recentlyAddedAlbums(limit: recentLimit)
            }
        case (.files, .albums):
            let files = FilesLibraryService.shared
            return {
                await files.scanIfNeeded()
                return files.albums(sortedBy: .title)
            }
        default:
            return nil
        }
    }

    /// Apple's playlists merge into the browse service's set rather than
    /// coming back as pages, so this pages by the set's size: the first page
    /// again (a playlist made since shows up), then on while it grows.
    private static func applePlaylists() async -> [PlayableContent] {
        let apple = AppleMusicBrowseService.shared
        var offset = 0
        for _ in 0 ..< maxPages {
            let before = apple.userPlaylists.count
            await apple.updateUsersApplePlaylists(offset: offset)
            let after = apple.userPlaylists.count
            guard after < rowLimit, offset == 0 || after > before else { break }
            offset = after
        }
        return Array(apple.userPlaylists)
    }

    // MARK: - Downloads

    /// Everything on this device — Cue's downloads, the Music app's and the
    /// Files folder's — the way Offline Mode reads it. It all plays with no
    /// network, which in a car is the point.
    static var hasDownloads: Bool {
        !OnDeviceLibrary.isEmpty
    }

    /// Every song on this device as one container, for Shuffle All.
    static var allDownloads: PlayableContent {
        OnDeviceLibrary.allSongsContainer
    }

    /// How many songs are on this device.
    static var downloadCount: Int {
        OnDeviceLibrary.allSongs.count
    }

    /// Albums, Artists and Songs over what's on this device, as the phone's
    /// Downloaded pages list them, each with its count.
    static func downloadListings() -> [Listing] {
        let albums = OnDeviceLibrary.groups(.albums, sortedBy: .title, descending: false)
        let artists = OnDeviceLibrary.groups(.artists, sortedBy: .title, descending: false)
        let songCount = downloadCount
        return [
            Listing(
                title: OnDeviceCollection.albums.title,
                systemImage: OnDeviceCollection.albums.systemImage,
                detail: count(albums.count, "album")
            ) {
                OnDeviceLibrary.groups(.albums, sortedBy: .title, descending: false).map(\.container)
            },
            Listing(
                title: OnDeviceCollection.artists.title,
                systemImage: OnDeviceCollection.artists.systemImage,
                detail: count(artists.count, "artist")
            ) {
                OnDeviceLibrary.groups(.artists, sortedBy: .title, descending: false).map(\.container)
            },
            Listing(
                title: "Songs",
                systemImage: "music.note",
                detail: count(songCount, "song"),
                shuffleAll: allDownloads,
                playsInOrder: true
            ) {
                OnDeviceLibrary.songs(sortedBy: .title, descending: false)
            },
        ]
    }

    /// The albums that arrived last, newest first.
    static func recentlyDownloaded() -> [PlayableContent] {
        Array(allRecentlyDownloaded().prefix(recentDownloadsLimit))
    }

    /// Every album on this device, newest first, behind the title of the
    /// Recently Downloaded cards.
    static let recentlyDownloadedListing = Listing(title: "Recently Downloaded", systemImage: "clock") {
        allRecentlyDownloaded()
    }

    private static func allRecentlyDownloaded() -> [PlayableContent] {
        OnDeviceLibrary.groups(.albums, sortedBy: .added, descending: true).map(\.container)
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        value == 1 ? "1 \(noun)" : "\(value.formatted()) \(noun)s"
    }

    // MARK: - Radio

    /// The Radio tab's stations: TuneIn's local and trending ones and Apple
    /// Music's live and personal ones, each while its provider is on — the
    /// phone's Radio tab, without the directory pages.
    static func stations() async -> [StationSection] {
        let features = CoreFeatures.shared
        let showsTuneIn = features.isEnabled(.tuneIn)
        let showsApple = features.isEnabled(.apple) && MusicAuthorization.currentStatus == .authorized
        let tuneIn = TuneInBrowseService.shared
        let apple = AppleMusicBrowseService.shared

        await withTaskGroup(of: Void.self) { group in
            if showsTuneIn {
                group.addTask { await tuneIn.load() }
            }
            if showsApple {
                group.addTask {
                    await apple.updateLiveRadioStations()
                    await apple.updateRadioStations(offset: 0)
                }
            }
        }

        let player = LocalPlaybackService.shared
        var sections: [StationSection] = []
        if showsTuneIn {
            sections.append(StationSection(title: "Local Radio", stations: tuneIn.localStations))
            sections.append(StationSection(title: "Trending", stations: tuneIn.trending))
        }
        if showsApple {
            sections.append(StationSection(title: MediaSearchService.apple.title, stations: apple.radioStations))
        }
        return sections.compactMap { section in
            let playable = section.stations.filter { player.canPlayLocally($0) }
            return playable.isEmpty ? nil : StationSection(title: section.title, stations: playable)
        }
    }

    // MARK: - Containers

    /// An album's or playlist's songs that this device can play, read the
    /// way the local queue expands it, so the list and what plays agree.
    static func tracks(in container: PlayableContent) async -> [PlayableContent] {
        let player = LocalPlaybackService.shared
        let tracks = await collect { offset in
            await player.containerTracks(for: container, offset: offset)
        }
        return tracks.filter { player.canPlayLocally($0) }
    }

    // MARK: - Paging

    /// Bounds every paging loop: a source that ignored `offset` would hand
    /// back its first page forever.
    private static let maxPages = 20

    /// Pages through `load` until a page comes back empty or adds nothing
    /// new, or there are `limit` rows. Sources that answer in one shot
    /// return everything at offset 0 and nothing after.
    private static func collect(
        limit: Int? = nil,
        _ load: (_ offset: Int) async -> [PlayableContent]
    ) async -> [PlayableContent] {
        let limit = limit ?? rowLimit
        var items: [PlayableContent] = []
        var seen = Set<String>()
        var offset = 0
        for _ in 0 ..< maxPages {
            let page = await load(offset)
            offset += page.count
            let fresh = page.filter { seen.insert($0.id).inserted }
            items += fresh
            guard !fresh.isEmpty, items.count < limit else { break }
        }
        return Array(items.prefix(limit))
    }
}
#endif
