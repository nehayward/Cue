import Defaults
import Foundation
import MusicKit
import MusicSearchKit
import Nuke
import Observation
import OSLog
import SonosKit
import UIKit
import WidgetKit

/// Keeps the album shelf widget's albums current: those played lately
/// (`PlayHistoryService`), those downloaded whole (`OnDeviceLibrary`) and
/// those widgets are set to (My Shelf, the Chosen shelf), each cover
/// written beside them, and the one playing. They're kept in the book
/// shelf's shape (`BookShelfWidgetState`, an album's artist as its author,
/// no place) in the App Group's `AlbumShelfWidget` folder, and WidgetKit is
/// asked to reload when they change. Beside them, the catalog My Shelf's
/// albums are picked from in Edit Widget: those, and every album in the
/// Plex, Apple Music and Files libraries, read every few hours.
///
/// It also answers the widget's Play and links (`play(albumID:)`,
/// `open(albumID:plays:)`), which name an album by its key.
///
/// `log stream --predicate 'subsystem == "dance.cue" AND category == "widgets"' --level debug`
@MainActor
final class AlbumShelfWidgetPublisher {
    static let shared = AlbumShelfWidgetPublisher()

    private static let log = Logger(subsystem: "dance.cue", category: "widgets")

    /// Albums kept on each shelf: as many as an extra large widget shows.
    private static let shelfLimit = 12
    /// The cover sizes written, the book shelf's: a shelf's first album,
    /// which the small widget and the large one's lead show bigger, and the
    /// rest.
    private static let leadCoverPoints = BookShelfWidgetPublisher.leadCoverPoints
    private static let coverPoints = BookShelfWidgetPublisher.coverPoints
    private static let coverRetryInterval: TimeInterval = 10 * 60

    private var published: BookShelfWidgetState?
    private var pending: Task<Void, Never>?
    private var isStarted = false
    private var backgroundObserver: (any NSObjectProtocol)?
    /// The albums on the shelves last made, by key, for the widget's Play
    /// and links.
    private var albums: [String: PlayableContent] = [:]
    /// The covers in the widget's folder, by file name.
    private lazy var writtenCovers: Set<String> = {
        let files = BookShelfWidgetState.directory(.albums).flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        return Set(files.filter { $0.hasSuffix(".jpg") })
    }()
    private var coversUnderWay: Set<String> = []
    private var coverFailures: [String: Date] = [:]
    private var activeObserver: (any NSObjectProtocol)?

    /// Every album in the libraries, for the catalog, read every
    /// `libraryInterval` and kept in Caches.
    private var libraryAlbums: [PlayableContent] = [] {
        didSet { _libraryByKey = nil }
    }
    /// `libraryAlbums` by key, for the chosen albums' lookup.
    private var _libraryByKey: [String: PlayableContent]?
    private var libraryByKey: [String: PlayableContent] {
        if let byKey = _libraryByKey { return byKey }
        let byKey = Dictionary(libraryAlbums.map { (Self.key(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        _libraryByKey = byKey
        return byKey
    }
    private var libraryRead: Date = .distantPast
    private var isReadingLibrary = false
    private static let libraryCacheName = "AlbumShelfWidgetLibrary"
    private static let libraryReadName = "AlbumShelfWidgetLibraryRead"
    private static let libraryInterval: TimeInterval = 6 * 3600
    /// At most this many from each library: a page is 100.
    private static let libraryPages = 50
    private var catalog: BookShelfWidgetState.Catalog?
    private var catalogSourceCount = -1
    /// The Apple Music storefront Edit Widget searches the catalog of; nil
    /// without Apple Music.
    private var storefront: String?
    /// Albums picked in Edit Widget from the Apple Music catalog, not in a
    /// library: looked up by id, and kept in Caches.
    private var fetchedAlbums: [String: PlayableContent] = [:]
    private var fetchingAlbums: Set<String> = []
    private var fetchFailures: [String: Date] = [:]
    private static let fetchedCacheName = "AlbumShelfWidgetFetched"
    private let thumbnails = WidgetCatalogThumbnails(folder: .albums)

    private init() {}

    /// Follows the history, the downloads and the player from now on, and
    /// writes the shelves a moment after launch.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        libraryAlbums = ShelfCache.load([PlayableContent].self, named: Self.libraryCacheName) ?? []
        libraryRead = ShelfCache.load(Date.self, named: Self.libraryReadName) ?? .distantPast
        fetchedAlbums = ShelfCache.load([String: PlayableContent].self, named: Self.fetchedCacheName) ?? [:]
        // As the catalog was last written: written before the library is
        // read again, it lost the storefront, and Edit Widget's Apple Music
        // search found nothing meanwhile.
        storefront = BookShelfWidgetState.Catalog.load(.albums)?.storefront
        observe()
        schedule(after: .seconds(4))
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                AlbumShelfWidgetPublisher.shared.publishNow()
            }
        }
        // A widget set to albums in Edit Widget since: nothing tells Cue,
        // so it looks as it comes back (`chosenBookIDs(in:)`).
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                AlbumShelfWidgetPublisher.shared.schedule(after: .seconds(1))
            }
        }
    }

    /// Reads every album in the libraries for the catalog, at most every
    /// `libraryInterval` (kept across launches) and only in front, never for
    /// a launch in the background, a page at a time.
    private func readLibraryIfDue() {
        guard !isReadingLibrary, Date.now.timeIntervalSince(libraryRead) > Self.libraryInterval, !OfflineMode.shared.isActive,
              UIApplication.shared.applicationState != .background else { return }
        isReadingLibrary = true
        Task {
            var albums: [PlayableContent] = []
            let features = CoreFeatures.shared
            if features.isEnabled(.plex) {
                for page in 0..<Self.libraryPages {
                    let rows = await PlexBrowseService.shared.updateUserAlbums(offset: page * 100)
                    albums += rows
                    if rows.count < 100 { break }
                }
            }
            // Never asks for access: only a library already allowed.
            if features.isEnabled(.apple), MusicAuthorization.currentStatus == .authorized {
                for page in 0..<Self.libraryPages {
                    let rows = await AppleMusicBrowseService.shared.libraryAlbums(offset: page * 100)
                    albums += rows
                    if rows.count < 100 { break }
                }
            }
            if features.isEnabled(.files) {
                albums += FilesLibraryService.shared.albums
            }
            // Edit Widget searches this storefront's catalog too; the one
            // kept stands when the country isn't answered.
            let hasApple = features.isEnabled(.apple) && MusicAuthorization.currentStatus == .authorized
            let storefront = hasApple ? (try? await MusicDataRequest.currentCountryCode) ?? self.storefront : nil
            if storefront != self.storefront {
                self.storefront = storefront
                catalogSourceCount = -1
            }
            isReadingLibrary = false
            libraryRead = .now
            ShelfCache.save(libraryRead, named: Self.libraryReadName)
            // A page that fails reads as the library's end (the services
            // answer nothing), so a read well short of the one kept, a server
            // out of reach, isn't taken: My Shelf's albums from it would
            // drop out of the catalog and off the widget.
            guard !albums.isEmpty, albums.count >= libraryAlbums.count * 9 / 10 else {
                Self.log.error("album shelf widget: library read short (\(albums.count) of \(self.libraryAlbums.count)), kept the last")
                return
            }
            libraryAlbums = albums
            ShelfCache.save(albums, named: Self.libraryCacheName)
            Self.log.info("album shelf widget: \(albums.count) library albums for the catalog")
            schedule(after: .seconds(1))
        }
    }

    func publishNow() {
        pending?.cancel()
        pending = nil
        publish()
    }

    // MARK: - Following

    /// Re-arms after every change, as `BookShelfWidgetPublisher` does. The
    /// player is followed by song and playing state, not its clock.
    private func observe() {
        withObservationTracking {
            _ = PlayHistoryService.shared.history
            _ = DownloadManager.shared.musicSummary
            let presented = PlaybackRoute.shared.presented
            _ = presented.isPlaying
            _ = presented.nowPlayingDisplay?.id
            // Where Play goes, shown beside it.
            _ = PlaybackRoute.shared.group?.nameWithCount
        } onChange: {
            Task { @MainActor in
                let publisher = AlbumShelfWidgetPublisher.shared
                publisher.schedule(after: .seconds(2))
                publisher.observe()
            }
        }
    }

    private func schedule(after delay: Duration) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            pending = nil
            publish()
        }
    }

    // MARK: - Writing

    private func publish() {
        let state = makeState()
        writeCoversMissing(in: state)
        writeCatalog()
        readLibraryIfDue()
        guard state != published else { return }
        do {
            try state.save(.albums)
        } catch {
            Self.log.error("album shelf widget: not written: \(error.localizedDescription, privacy: .public)")
            return
        }
        // The discography widget draws the album in the player and the
        // speaker from here: reloaded only when they change, as its own
        // albums aren't on these shelves.
        if published?.albumInPlayer != state.albumInPlayer || published?.albumInPlayerIsPlaying != state.albumInPlayerIsPlaying
            || published?.speaker != state.speaker {
            WidgetCenter.shared.reloadTimelines(ofKind: DiscographyArtist.widgetKind)
        }
        published = state
        WidgetCenter.shared.reloadTimelines(ofKind: BookShelfWidgetState.Albums.widgetKind)
        removeUnusedCovers(keeping: state)
        let counts = BookShelfWidgetState.Albums.Shelf.allCases.map { "\($0.rawValue) \(state.albums(on: $0).count)" }.joined(separator: ", ")
        // Notice, not info: info isn't kept, and a write from Cue woken in
        // the background was missing from the phone's log.
        Self.log.notice("album shelf widget: written (\(counts, privacy: .public)), playing \(state.isPlaying)")
    }

    /// The shelves, and `albums` filled from them.
    private func makeState() -> BookShelfWidgetState {
        let recentlyPlayed = Array(PlayHistoryService.shared.plays.filter { [.album, .libraryAlbum].contains($0.content.type) && Self.isPlayableHere($0) })
        let downloaded = OnDeviceLibrary.albums.sorted { $0.latestAdded > $1.latestAdded }.map(\.container)
        // The albums widgets are set to (My Shelf), from wherever Cue has them.
        let chosenIDs = BookShelfWidgetState.chosenBookIDs(in: .albums)
        let chosen = chosenIDs.isEmpty ? [] : chosenIDs.sorted().compactMap { id in
            libraryByKey[id] ?? fetchedAlbums[id] ?? (recentlyPlayed + downloaded).first { Self.key(for: $0) == id }
        }
        fetchAppleAlbums(chosenIDs.filter { id in !chosen.contains { Self.key(for: $0) == id } })

        var contents: [String: PlayableContent] = [:]
        var shelves: [String: [BookShelfWidgetState.Book]] = [:]
        for (shelf, list) in [
            (BookShelfWidgetState.Albums.Shelf.recentlyPlayed, recentlyPlayed),
            (.downloaded, downloaded),
            (.chosen, chosen),
        ] {
            var seen: Set<String> = []
            var entries: [BookShelfWidgetState.Book] = []
            for album in list {
                let key = Self.key(for: album)
                // Every chosen album: each widget picks its own from them.
                guard shelf == .chosen || entries.count < Self.shelfLimit, seen.insert(key).inserted else { continue }
                contents[key] = album
                entries.append(entry(for: album, key: key, isLead: entries.isEmpty || shelf == .chosen))
            }
            shelves[shelf.rawValue] = entries
        }
        albums = contents

        let presented = PlaybackRoute.shared.presented
        let loaded = contents.first { isLoaded($0.value, on: presented) }?.key
        let inPlayer = Self.albumKey(in: presented)
        return BookShelfWidgetState(
            shelves: shelves,
            loadedID: loaded,
            isPlaying: loaded != nil && presented.isPlaying,
            chapter: nil,
            needsServer: false,
            speaker: PlaybackRoute.shared.group?.nameWithCount,
            albumInPlayer: inPlayer,
            albumInPlayerIsPlaying: inPlayer != nil && presented.isPlaying
        )
    }

    /// The key of the album the song `controller` shows is from, on a shelf
    /// or not, for the discography widget: on this device the album its
    /// queue was played from, else the album the song names.
    private static func albumKey(in controller: any PlaybackController) -> String? {
        if controller.group == nil, let source = LocalPlaybackService.shared.source {
            return [.album, .libraryAlbum].contains(source.content.type) ? key(for: source) : nil
        }
        guard let song = controller.nowPlayingDisplay, let albumID = song.metadata?.albumID else { return nil }
        return AudiobookProgressStore.key(service: song.content.service, id: albumID)
    }

    /// Writes the catalog Edit Widget's Albums offers (`WidgetAlbumQuery`),
    /// in title order, when the albums it's made from have changed, and
    /// the small covers it lists them with.
    private func writeCatalog() {
        let recentlyPlayed = PlayHistoryService.shared.plays.filter { [.album, .libraryAlbum].contains($0.content.type) && Self.isPlayableHere($0) }
        let downloaded = OnDeviceLibrary.albums.map(\.container)
        let everyAlbum = Array(recentlyPlayed) + downloaded + libraryAlbums
        guard everyAlbum.count != catalogSourceCount else { return }
        catalogSourceCount = everyAlbum.count
        var seen: Set<String> = []
        var unique: [(key: String, content: PlayableContent)] = []
        let albums = everyAlbum.compactMap { album -> BookShelfWidgetState.Book? in
            let key = Self.key(for: album)
            guard seen.insert(key).inserted else { return nil }
            unique.append((key, album))
            return BookShelfWidgetState.Book(id: key, title: album.title, author: album.subtitle, fraction: nil, remaining: nil, duration: 0, isFinished: false, isDownloaded: false, cover: nil)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        // The ones played and downloaded first, as Edit Widget leads with them.
        thumbnails.writeMissing(for: unique)
        let catalog = BookShelfWidgetState.Catalog(books: albums, storefront: storefront)
        guard catalog != self.catalog else { return }
        self.catalog = catalog
        Task.detached(priority: .utility) {
            try? catalog.save(.albums)
        }
        Self.log.info("album shelf widget: catalog of \(albums.count) albums")
    }

    /// Looks up the Apple Music albums among `ids` (picked in Edit Widget
    /// from its catalog) that Cue doesn't have, and writes the shelves again
    /// once they're in. Never asks for Apple Music access.
    private func fetchAppleAlbums(_ ids: [String]) {
        let prefix = AudiobookProgressStore.key(service: .apple, id: "")
        // Catalog ids only (a library or downloaded album's isn't one), and
        // one not found not asked for again within the hour: the shelves are
        // written at every change of song.
        let wanted = ids.filter { id in
            let number = id.dropFirst(prefix.count)
            return id.hasPrefix(prefix) && !number.isEmpty && number.allSatisfy(\.isNumber)
                && !fetchingAlbums.contains(id) && fetchedAlbums[id] == nil
                && Date.now.timeIntervalSince(fetchFailures[id] ?? .distantPast) > 3600
        }
        guard !wanted.isEmpty, MusicAuthorization.currentStatus == .authorized else { return }
        fetchingAlbums.formUnion(wanted)
        Task {
            var found = 0
            for id in wanted {
                if let album = try? await MusicSearchService.shared.lookup(id: String(id.dropFirst(prefix.count))) as Album? {
                    fetchedAlbums[id] = album.toPlayable
                    found += 1
                } else {
                    fetchFailures[id] = .now
                }
            }
            fetchingAlbums.subtract(wanted)
            guard found > 0 else { return }
            ShelfCache.save(fetchedAlbums, named: Self.fetchedCacheName)
            schedule(after: .seconds(1))
        }
    }

    /// Whether `album` plays on this device now: downloaded whole, or from
    /// a service switched on here and, for a server, signed in to. The play
    /// history syncs through iCloud, so it holds albums from servers only
    /// another device uses: one tapped did nothing ("Nothing here can play
    /// on this device").
    private static func isPlayableHere(_ album: PlayableContent) -> Bool {
        if OnDeviceLibrary.isContainer(album) { return true }
        let features = CoreFeatures.shared
        let isSetUp = switch album.content.service {
        case .apple: features.isEnabled(.apple)
        case .plex: features.isEnabled(.plex) && MusicSearchService.shared.plexServerID != nil
        case .subsonic: features.isEnabled(.subsonic) && SubsonicAPI.shared.isConfigured
        case .files: features.isEnabled(.files)
        default: false
        }
        return isSetUp && LocalPlaybackService.shared.canPlayContainerLocally(album)
    }

    static func key(for album: PlayableContent) -> String {
        AudiobookProgressStore.key(for: album)
    }

    /// Whether the song `controller` shows is from `album`. On this device,
    /// by where the queue's song came from (`LocalPlaybackService.source`),
    /// which the song's own metadata often doesn't say in the album's terms
    /// (a Plex song's album id isn't the album's key, a downloaded album's
    /// is the device's own); on a speaker, or with no source, by the album
    /// id the song names on the same service, else its album's title and
    /// artist (two "Greatest Hits" aren't one album).
    private func isLoaded(_ album: PlayableContent, on controller: any PlaybackController) -> Bool {
        if controller.group == nil, let source = LocalPlaybackService.shared.source {
            return Self.key(for: source) == Self.key(for: album)
        }
        guard let song = controller.nowPlayingDisplay, let metadata = song.metadata else { return false }
        if let albumID = metadata.albumID, song.content.service == album.content.service, albumID == album.content.id {
            return true
        }
        guard let title = metadata.album, !title.isEmpty, title.localizedCaseInsensitiveCompare(album.title) == .orderedSame else { return false }
        guard let artist = metadata.artist, !artist.isEmpty else { return true }
        return album.subtitle.localizedCaseInsensitiveContains(artist)
    }

    private func entry(for album: PlayableContent, key: String, isLead: Bool) -> BookShelfWidgetState.Book {
        // The cover at this size, else one written before until it is.
        let cover = coverSource(for: album, key: key, isLead: isLead).flatMap { source in
            writtenCovers.contains(source.name) ? source.name : writtenCovers.first { $0.hasPrefix(BookShelfWidgetState.coverPrefix(for: key)) }
        }
        return BookShelfWidgetState.Book(id: key, title: album.title, author: album.subtitle, fraction: nil, remaining: nil, duration: 0, isFinished: false, isDownloaded: false, cover: cover)
    }

    // MARK: - Covers

    private func coverSource(for album: PlayableContent, key: String, isLead: Bool) -> (name: String, request: ImageRequest)? {
        guard let url = album.artwork ?? album.thumbnail else { return nil }
        let points = isLead ? Self.leadCoverPoints : Self.coverPoints
        let request = ContentArtworkView.artworkRequest(for: album, url: url, preferredSize: points)
        let pixels = Int(ContentArtworkView.maxPixelSize(for: points))
        return (BookShelfWidgetState.coverName(for: key, source: url.absoluteString, pixels: pixels), request)
    }

    /// Fetches and writes the covers the shelves have no file for at their
    /// size yet, and writes the shelves again once one lands.
    private func writeCoversMissing(in state: BookShelfWidgetState) {
        for shelf in BookShelfWidgetState.Albums.Shelf.allCases {
            for (index, entry) in state.albums(on: shelf).enumerated() {
                // At the size `entry(for:)` names: a chosen album's is the
                // lead's, as any can lead a My Shelf.
                guard let album = albums[entry.id], let source = coverSource(for: album, key: entry.id, isLead: index == 0 || shelf == .chosen),
                      !writtenCovers.contains(source.name), !coversUnderWay.contains(source.name),
                      Date.now.timeIntervalSince(coverFailures[source.name] ?? .distantPast) > Self.coverRetryInterval,
                      let url = BookShelfWidgetState.coverURL(named: source.name, in: .albums) else { continue }
                coversUnderWay.insert(source.name)
                Task {
                    let written = await BookShelfWidgetPublisher.writeImage(source.request, to: url, quality: 0.85)
                    coversUnderWay.remove(source.name)
                    guard written else {
                        coverFailures[source.name] = .now
                        return
                    }
                    coverFailures[source.name] = nil
                    writtenCovers.insert(source.name)
                    schedule(after: .seconds(1))
                }
            }
        }
    }

    /// Takes away the covers no shelf names any more.
    private func removeUnusedCovers(keeping state: BookShelfWidgetState) {
        guard let directory = BookShelfWidgetState.directory(.albums) else { return }
        let named = Set(BookShelfWidgetState.Albums.Shelf.allCases.flatMap { state.albums(on: $0).compactMap(\.cover) })
        for name in writtenCovers where !named.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            writtenCovers.remove(name)
        }
    }

    // MARK: - The widget's taps

    /// The album the widget names, from the shelves made now if none have
    /// been since launch (a Play that launched Cue in the background).
    private func album(withID id: String) -> PlayableContent? {
        if albums[id] == nil {
            _ = makeState()
        }
        // A Plex album on a discography widget.
        return albums[id] ?? libraryByKey[id] ?? fetchedAlbums[id] ?? DiscographyWidgetPublisher.shared.album(withID: id)
    }

    /// `album(withID:)`, else the album looked up by its key: an Apple Music
    /// album picked from its catalog and tapped before Cue had looked it
    /// up, or a Plex album on a discography widget whose cache iOS cleared.
    private func findAlbum(withID id: String) async -> PlayableContent? {
        if let album = album(withID: id) { return album }
        let apple = AudiobookProgressStore.key(service: .apple, id: "")
        let plex = AudiobookProgressStore.key(service: .plex, id: "")
        let content: PlayableContent
        if id.hasPrefix(apple), MusicAuthorization.currentStatus == .authorized,
           let album = try? await MusicSearchService.shared.lookup(id: String(id.dropFirst(apple.count))) as Album? {
            content = album.toPlayable
        } else if id.hasPrefix(plex), let album = await MusicSearchService.shared.lookupPlexAlbum(id: String(id.dropFirst(plex.count))) {
            content = album
        } else {
            return nil
        }
        fetchedAlbums[id] = content
        ShelfCache.save(fetchedAlbums, named: Self.fetchedCacheName)
        return content
    }

    /// The widget's Play: the album playing or paused in the player plays
    /// or pauses where it is; any other plays from its start, where the
    /// route points, as a card's Play does. The speakers are looked for
    /// first, so an album a speaker plays reads as loaded after a launch in
    /// the background (before, Pause restarted it from its first song).
    func play(albumID: String) async {
        let began = ContinuousClock.now
        guard let album = await findAlbum(withID: albumID) else {
            Self.log.error("album shelf widget: no album \(albumID, privacy: .public) to play")
            #if DEBUG && os(iOS)
            PhoneLogFile.writeNow()
            #endif
            return
        }
        await PlayDestinationRouter.loadSpeakersIfNeeded()
        let presented = PlaybackRoute.shared.presented
        let expected: Bool
        let speaker = SpeakerSend()
        if isLoaded(album, on: presented) {
            Self.log.notice("album shelf widget: play/pause \(album.title, privacy: .public)")
            expected = !presented.isPlaying
            await presented.togglePlayback()
        } else {
            Self.log.notice("album shelf widget: play \(album.title, privacy: .public)")
            expected = true
            await PlayDestinationRouter.play(album, position: .replace) { group, position in
                speaker.isSent = true
                var item = QueueItem(playableContent: album, group: group, position: position)
                item.done = { speaker.landed = .now }
                QueueManager.shared.addToQueue(item: item)
            }
        }
        // The player says it's playing a moment after it's told to, and, from
        // another album, that this one is loaded: written at once, the
        // widget's Pause went back to Play, and a second tap paused what had
        // just started. Written as soon as it says so. A speaker is given
        // the album after this returns (a Plex album looked up and queued a
        // song at a time), so the wait runs while it's being given it, then
        // 3 s at most.
        while !isSettled(on: album, playing: expected) {
            let now = ContinuousClock.now
            if speaker.isSent, speaker.landed == nil {
                if now - began > .seconds(15) { break }
            } else if now - (speaker.landed ?? began) > .seconds(3) {
                break
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        let landed = speaker.landed.map { ", the speaker had it at \(Self.milliseconds($0 - began)) ms" } ?? ""
        logPlayer(expected: expected, at: "\(Self.milliseconds(ContinuousClock.now - began)) ms after the tap\(landed)")
        publishNow()
        #if DEBUG && os(iOS)
        // Woken in the background, Cue may be suspended before its log is
        // written: these lines are what says whether the album sounded.
        Task {
            try? await Task.sleep(for: .seconds(3))
            logPlayer(expected: expected, at: "3 s after that")
            PhoneLogFile.writeNow()
        }
        #endif
    }

    /// Whether, and when, a speaker was given a widget's album.
    @MainActor
    private final class SpeakerSend {
        var isSent = false
        var landed: ContinuousClock.Instant?
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

    /// Whether the player says what a widget's Play asked: `album` playing,
    /// or paused.
    private func isSettled(on album: PlayableContent, playing: Bool) -> Bool {
        let presented = PlaybackRoute.shared.presented
        return presented.isPlaying == playing && (!playing || isLoaded(album, on: presented))
    }

    /// What the player says after a widget's Play, with Apple Music's own
    /// player beside it: an Apple Music album started from the background
    /// once made no sound.
    private func logPlayer(expected: Bool, at time: String) {
        let presented = PlaybackRoute.shared.presented
        let appState = switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
        Self.log.notice("album shelf widget: \(time, privacy: .public), playing \(presented.isPlaying) (wanted \(expected)), Apple Music player \(String(describing: ApplicationMusicPlayer.shared.state.playbackStatus), privacy: .public), Cue \(appState, privacy: .public)")
    }

    /// The widget's `cue://album` link: the album's page, in place of any
    /// opened before and over whatever else is on screen, or with `plays`,
    /// the player, and the widget's Play or Pause done in it.
    func open(albumID: String, plays: Bool) async {
        guard let album = await findAlbum(withID: albumID) else {
            Self.log.error("album shelf widget: no album \(albumID, privacy: .public) to open")
            return
        }
        Self.log.notice("album shelf widget: \(plays ? "open playing" : "open", privacy: .public) \(album.title, privacy: .public)")
        MediaDetailPresenter.dismissPresented()
        guard plays else {
            // The player goes down first: a page presented in the same
            // turn went up on the player and came down with it.
            if Router.main.isPlayerPresented {
                Router.main.isPlayerPresented = false
                try? await Task.sleep(for: .milliseconds(100))
            }
            MediaDetailPresenter.present(album)
            return
        }
        Router.main.isPlayerPresented = true
        await play(albumID: albumID)
    }
}
