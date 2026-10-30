import Defaults
import Foundation
import MusicKit
import OSLog
import SonosKit
import UIKit
import WidgetKit

/// What the discography widget can't read itself: the albums of the Plex
/// artists widgets are set to (`DiscographyArtist`, in the App Group), and
/// every artist on the server for Edit Widget's picker, since only Cue can
/// reach the server; and for an Apple Music artist, whose releases the
/// widget reads from Apple's public catalog, which of them are albums
/// (`DiscographyArtist.AlbumList`, MusicKit's `fullAlbums`), for Studio
/// Albums.
///
/// It also keeps the albums it read by key, for the widget's Play and links
/// (`album(withID:)`, through the album shelf's).
@MainActor
final class DiscographyWidgetPublisher {
    static let shared = DiscographyWidgetPublisher()

    private static let log = Logger(subsystem: "dance.cue", category: "widgets")
    private static let prefix = AudiobookProgressStore.key(service: .plex, id: "")
    /// How long an artist's albums, and the list of artists, stand.
    private static let artistInterval: TimeInterval = 6 * 3600
    private static let listInterval: TimeInterval = 24 * 3600
    /// How long after a list read short it's read again.
    private static let listRetry: TimeInterval = 3600
    /// How long the files of an artist no widget shows are kept.
    private static let unusedFor: TimeInterval = 14 * 24 * 3600
    /// The albums kept an artist: more than the widest widget shows.
    private static let albumLimit = 40
    private static let albumsCacheName = "DiscographyWidgetAlbums"

    private var isRefreshing = false
    private var albums: [String: PlayableContent]?
    /// When Plex's artists last read short of the list kept.
    private var listReadShortAt: Date?
    private var activeObserver: (any NSObjectProtocol)?

    private init() {}

    /// Reads what's due a moment after Cue comes to the front, and finishes
    /// with time asked of iOS if Cue leaves it: opened only to change
    /// something, Cue is often in the background within seconds. Not for a
    /// launch in the background: a widget's Play wakes Cue for that alone.
    func start() {
        guard activeObserver == nil else { return }
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Task { await DiscographyWidgetPublisher.shared.refresh(after: .seconds(1)) }
            }
        }
    }

    private func refresh(after delay: Duration) async {
        try? await Task.sleep(for: delay)
        guard !isRefreshing, !OfflineMode.shared.isActive else { return }
        isRefreshing = true
        let time = BackgroundTime(name: "Discography widget")
        defer {
            isRefreshing = false
            time.end()
        }
        let chosen = BookShelfWidgetState.chosenBookIDs(in: .discography)
        DiscographyArtist.removeUnused(keeping: chosen, olderThan: Self.unusedFor)
        var wrote = await writeAlbumLists(for: chosen.filter { $0.hasPrefix(Self.applePrefix) }.sorted())
        let hasPlex = CoreFeatures.shared.isEnabled(.plex) && MusicSearchService.shared.plexServerID != nil
        if hasPlex {
            var known = albums ?? loadAlbums()
            var changed = false
            for id in chosen.sorted() where id.hasPrefix(Self.prefix) {
                if let kept = DiscographyArtist.load(id: id), Date.now.timeIntervalSince(kept.readAt) < Self.artistInterval { continue }
                if await write(artistID: id, into: &known) {
                    wrote = true
                    changed = true
                }
            }
            // Only the albums of the artists still shown.
            let shown = Set(chosen.compactMap(DiscographyArtist.load(id:)).flatMap { $0.releases.map(\.id) })
            let count = known.count
            known = known.filter { shown.contains($0.key) }
            if changed || known.count != count {
                ShelfCache.save(known, named: Self.albumsCacheName)
            }
            albums = known
        }
        if wrote {
            WidgetCenter.shared.reloadTimelines(ofKind: DiscographyArtist.widgetKind)
        }
        if hasPlex {
            await writeArtistListIfDue()
        }
    }

    // MARK: - Apple Music's albums

    private static let applePrefix = AudiobookProgressStore.key(service: .apple, id: "")
    /// How long Apple's list of an artist's albums stands.
    private static let albumListInterval: TimeInterval = 24 * 3600

    /// Writes which of each Apple Music artist's releases Apple counts as
    /// albums, once a day. Never asks for Apple Music access.
    private func writeAlbumLists(for ids: [String]) async -> Bool {
        guard !ids.isEmpty, CoreFeatures.shared.isEnabled(.apple), MusicAuthorization.currentStatus == .authorized else { return false }
        var wrote = false
        for id in ids {
            if let kept = DiscographyArtist.albumList(for: id), Date.now.timeIntervalSince(kept.readAt) < Self.albumListInterval { continue }
            guard let albums = await Self.fullAlbumIDs(of: String(id.dropFirst(Self.applePrefix.count))), !albums.isEmpty else {
                Self.log.error("discography widget: no album list read for \(id, privacy: .public)")
                continue
            }
            do {
                try DiscographyArtist.save(DiscographyArtist.AlbumList(ids: albums, readAt: .now), for: id)
                wrote = true
                Self.log.notice("discography widget: \(albums.count) albums by Apple's count for \(id, privacy: .public)")
            } catch {
                Self.log.error("discography widget: album list for \(id, privacy: .public) not written: \(error.localizedDescription, privacy: .public)")
            }
        }
        return wrote
    }

    /// The catalog ids of an artist's full-length albums, ten batches at
    /// most, as the artist page reads them.
    private static func fullAlbumIDs(of artistID: String) async -> [String]? {
        var request = MusicCatalogResourceRequest<MusicKit.Artist>(matching: \.id, equalTo: MusicItemID(artistID))
        request.properties = [.fullAlbums]
        guard let artist = try? await request.response().items.first, var batch = artist.fullAlbums else { return nil }
        var ids = batch.map(\.id.rawValue)
        for _ in 1..<10 {
            guard batch.hasNextBatch, let next = try? await batch.nextBatch() else { break }
            ids += next.map(\.id.rawValue)
            batch = next
        }
        return ids
    }

    /// Reads a Plex artist's albums, newest first, and writes them with
    /// their covers and the artist's photo, noting each album in `known`
    /// for the widget's taps. A read that brings nothing leaves what was
    /// written.
    private func write(artistID key: String, into known: inout [String: PlayableContent]) async -> Bool {
        let id = String(key.dropFirst(Self.prefix.count))
        let found = await MusicSearchService.shared.lookupPlexArtistAlbums(id: id)
        guard !found.isEmpty else {
            Self.log.error("discography widget: no albums read for \(key, privacy: .public)")
            return false
        }
        let artist = await MusicSearchService.shared.lookupPlexArtist(id: id)
        let newestFirst = found
            .sorted { ($0.metadata?.albumYear ?? .distantPast) > ($1.metadata?.albumYear ?? .distantPast) }
            .prefix(Self.albumLimit)
        var releases: [DiscographyArtist.Release] = []
        for album in newestFirst {
            let albumKey = AlbumShelfWidgetPublisher.key(for: album)
            known[albumKey] = album
            let cover = await writeImage(of: album, url: album.thumbnail ?? album.artwork, for: key)
            releases.append(.init(id: albumKey, title: album.title, released: album.metadata?.albumYear, cover: cover))
        }
        var photo: String?
        if let artist {
            photo = await writeImage(of: artist, url: artist.thumbnail ?? artist.artwork, for: key)
        }
        let written = DiscographyArtist(
            id: key,
            name: artist?.title ?? found.first?.metadata?.artist ?? "Artist",
            photo: photo,
            releases: releases,
            readAt: .now
        )
        do {
            try written.save()
        } catch {
            Self.log.error("discography widget: \(key, privacy: .public) not written: \(error.localizedDescription, privacy: .public)")
            return false
        }
        Self.log.notice("discography widget: \(written.name, privacy: .public), \(releases.count) albums")
        return true
    }

    /// An image for the widget, fetched through the phone's own image
    /// cache unless it's written already; its file name.
    private func writeImage(of content: PlayableContent, url: URL?, for artistID: String) async -> String? {
        guard let url else { return nil }
        let name = DiscographyArtist.imageName(for: artistID, source: url.absoluteString)
        guard let file = DiscographyArtist.imageURL(named: name) else { return nil }
        if FileManager.default.fileExists(atPath: file.path) { return name }
        let request = ContentArtworkView.artworkRequest(for: content, url: url, preferredSize: 100)
        return await BookShelfWidgetPublisher.writeImage(request, to: file, quality: 0.85) ? name : nil
    }

    /// Every artist on the Plex server, by name, for Edit Widget, once a
    /// day, and at once for a new server. A page that fails reads as the
    /// end of the list (Plex answers nothing), so a list well short of the
    /// one kept from the same server isn't taken, and is read again in an
    /// hour.
    private func writeArtistListIfDue() async {
        let kept = BookShelfWidgetState.Catalog.load(.discography)
        let server = MusicSearchService.shared.plexServerID
        let isSameServer = kept?.server == server
        if isSameServer, let readAt = kept?.readAt, Date.now.timeIntervalSince(readAt) < Self.listInterval { return }
        if isSameServer, let listReadShortAt, Date.now.timeIntervalSince(listReadShortAt) < Self.listRetry { return }
        var artists: [PlayableContent] = []
        for page in 0..<100 {
            let rows = await PlexBrowseService.shared.artists(offset: page * 100)
            artists += rows
            if rows.count < 100 { break }
        }
        let keptCount = isSameServer ? kept?.books.count ?? 0 : 0
        guard !artists.isEmpty, artists.count >= keptCount * 9 / 10 else {
            listReadShortAt = .now
            Self.log.error("discography widget: Plex's artists read short (\(artists.count) of \(keptCount)), kept the list")
            return
        }
        listReadShortAt = nil
        var seen: Set<String> = []
        let books = artists
            .compactMap { artist -> BookShelfWidgetState.Book? in
                let key = AudiobookProgressStore.key(for: artist)
                guard seen.insert(key).inserted else { return nil }
                return BookShelfWidgetState.Book(id: key, title: artist.title, author: "", fraction: nil, remaining: nil, duration: 0, isFinished: false, isDownloaded: false, cover: nil)
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let catalog = BookShelfWidgetState.Catalog(books: books, readAt: .now, server: server)
        await Task.detached(priority: .utility) {
            try? catalog.save(.discography)
        }.value
        Self.log.notice("discography widget: \(books.count) Plex artists for Edit Widget")
    }

    // MARK: - The widget's taps

    /// A Plex album the widget shows, by key.
    func album(withID id: String) -> PlayableContent? {
        if albums == nil {
            albums = loadAlbums()
        }
        return albums?[id]
    }

    private func loadAlbums() -> [String: PlayableContent] {
        ShelfCache.load([String: PlayableContent].self, named: Self.albumsCacheName) ?? [:]
    }
}
