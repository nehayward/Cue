import Foundation
import MusicSearchKit
import SonosKit
import WatchSync

/// Answers the watch when it browses the iPhone's libraries (`WatchRequest`):
/// pages of Plex and Subsonic playlists, albums and artists, fetched with
/// this iPhone's accounts the way its own library screens fetch them, and
/// adding or removing one through `WatchSyncService` — the same as Add to
/// Apple Watch here. WatchConnectivity wakes Cue for a request if it isn't
/// running.
///
/// Pages are cut to `WatchReply.pageSize` rows whatever the server pages
/// by (Subsonic hands every artist over at once), so a reply stays inside
/// what a message can carry. What a list has fetched is kept while the
/// watch pages through it, and fetched afresh when it starts at the top.
@MainActor
final class WatchBrowseServer {
    static let shared = WatchBrowseServer()

    private struct Listing {
        var items: [PlayableContent] = []
        var isComplete = false
    }

    private var listings: [WatchBrowsePath: Listing] = [:]
    /// What pages have shown, so adding one finds the item itself rather
    /// than a stand-in rebuilt from the reference.
    private var served: [WatchContentRef: PlayableContent] = [:]

    private init() {}

    func reply(to request: WatchRequest) async -> WatchReply {
        WatchSyncService.shared.refreshSessionState()
        switch request {
        case let .browse(path, offset):
            return .page(await page(path, offset: offset))
        case let .add(ref, quality):
            return await add(ref, quality: quality)
        case let .remove(ref):
            WatchSyncService.shared.remove(content(for: ref))
            return .removed
        }
    }

    // MARK: - Pages

    private func page(_ path: WatchBrowsePath, offset: Int) async -> WatchBrowsePage {
        let music = MusicSearchService.shared
        switch path {
        case .root:
            served.removeAll()
            listings.removeAll()
            var sources: [WatchBrowseItem] = []
            if music.isPlexAuthorized, music.plexServerID != nil {
                sources.append(WatchBrowseItem(id: "plex", title: WatchSource.plex.title, symbol: "server.rack", destination: .source(.plex)))
            }
            if music.isSubsonicConfigured {
                sources.append(WatchBrowseItem(id: "subsonic", title: WatchSource.subsonic.title, symbol: "externaldrive.connected.to.line.below", destination: .source(.subsonic)))
            }
            return WatchBrowsePage(
                title: "iPhone",
                items: sources,
                message: sources.isEmpty ? "Set up Plex or Subsonic in Cue on your iPhone to browse it here." : nil
            )

        case let .source(source):
            let sections: [WatchBrowseSection] = switch source {
            case .plex: [.playlists, .albums, .artists]
            case .subsonic: [.playlists, .recentlyAdded, .albums, .artists]
            }
            return WatchBrowsePage(
                title: source.title,
                items: sections.map { WatchBrowseItem(id: $0.rawValue, title: $0.title, symbol: $0.symbol, destination: .section(source, $0)) }
            )

        case .section, .artist:
            if offset == 0 {
                listings[path] = nil
            }
            var listing = listings[path] ?? Listing()
            // Bounded: a source that ignored `offset` and kept answering
            // with new rows would otherwise never stop.
            var rounds = 0
            while listing.items.count < offset + WatchReply.pageSize, !listing.isComplete, rounds < 20 {
                rounds += 1
                let fetched = await fetch(path, offset: listing.items.count)
                let known = Set(listing.items.map(\.id))
                let fresh = fetched.filter { !known.contains($0.id) }
                if fresh.isEmpty {
                    listing.isComplete = true
                } else {
                    listing.items += fresh
                }
            }
            listings[path] = listing

            let slice = listing.items.dropFirst(offset).prefix(WatchReply.pageSize)
            let next = offset + slice.count
            let hasMore = !slice.isEmpty && (next < listing.items.count || !listing.isComplete)
            return WatchBrowsePage(
                title: title(of: path),
                items: slice.compactMap(item(for:)),
                nextOffset: hasMore ? next : nil,
                container: container(of: path),
                message: listing.items.isEmpty ? "Nothing here." : nil
            )
        }
    }

    /// One page of a list from the server, as the iPhone's library
    /// screens fetch it. Lists that come whole answer at offset 0 only.
    private func fetch(_ path: WatchBrowsePath, offset: Int) async -> [PlayableContent] {
        let music = MusicSearchService.shared
        switch path {
        case .section(.plex, .playlists):
            guard offset == 0 else { return [] }
            await PlexBrowseService.shared.updateUserPlaylists()
            return Array(PlexBrowseService.shared.userPlaylists)
        case .section(.plex, .albums):
            return await PlexBrowseService.shared.updateUserAlbums(offset: offset)
        case .section(.plex, .artists):
            return await PlexBrowseService.shared.artists(offset: offset)
        case .section(.plex, .recentlyAdded):
            return []
        case .section(.subsonic, .playlists):
            return await music.subsonicUserPlaylists(offset: offset)
        case .section(.subsonic, .albums):
            return await music.subsonicAlbums(offset: offset)
        case .section(.subsonic, .artists):
            return await music.subsonicArtists(offset: offset)
        case .section(.subsonic, .recentlyAdded):
            return await music.subsonicRecentAlbums(offset: offset)
        case let .artist(ref):
            guard offset == 0 else { return [] }
            switch ref.source {
            case .plex:
                return await music.lookupPlexArtistAlbums(id: ref.id)
            case .subsonic:
                return await music.lookupSubsonicArtistWithAlbums(id: ref.id)?.albums ?? []
            }
        case .root, .source:
            return []
        }
    }

    private func title(of path: WatchBrowsePath) -> String {
        switch path {
        case .root: "iPhone"
        case let .source(source): source.title
        case let .section(_, section): section.title
        case let .artist(ref): ref.title
        }
    }

    /// An artist's page offers the artist whole, where that can go on the
    /// watch (Subsonic).
    private func container(of path: WatchBrowsePath) -> WatchBrowseItem? {
        guard case let .artist(ref) = path, let item = item(for: content(for: ref)), item.content != nil else { return nil }
        return item
    }

    /// A row for an album, playlist or artist: an artist opens on its
    /// albums, and whatever the watch can take whole carries its reference.
    /// Nil for anything else.
    private func item(for content: PlayableContent) -> WatchBrowseItem? {
        guard let source = WatchSource(content.content.service) else { return nil }
        let kind: WatchCollection.Kind
        switch content.content.type {
        case .album: kind = .album
        case .playlist: kind = .playlist
        case .artist: kind = .artist
        default: return nil
        }
        let ref = WatchContentRef(
            source: source,
            kind: kind,
            id: content.content.id,
            title: content.title,
            subtitle: content.metadata?.artist ?? content.subtitle,
            artworkURL: content.thumbnail ?? content.artwork
        )
        served[ref] = content
        let canAdd = WatchSyncService.shared.canAdd(content)
        guard canAdd || kind == .artist else { return nil }
        return WatchBrowseItem(
            id: content.id,
            title: ref.title,
            subtitle: ref.subtitle,
            artworkURL: ref.artworkURL,
            destination: kind == .artist ? .artist(ref) : nil,
            content: canAdd ? ref : nil,
            collectionKey: canAdd ? DownloadManager.containerKey(for: content) : nil
        )
    }

    /// The item a reference came from, or one rebuilt from it — enough for
    /// the track fetch, which goes by service, type and id.
    private func content(for ref: WatchContentRef) -> PlayableContent {
        if let content = served[ref] { return content }
        let type: ContentType = switch ref.kind {
        case .album, .songs: .album
        case .playlist: .playlist
        case .artist: .artist
        }
        return PlayableContent(
            title: ref.title,
            subtitle: ref.subtitle,
            thumbnail: ref.artworkURL,
            artwork: ref.artworkURL,
            content: MediaContent(service: ref.source.service, id: ref.id, type: type, location: nil)
        )
    }

    // MARK: - Adding

    private func add(_ ref: WatchContentRef, quality: WatchDownloadQuality?) async -> WatchReply {
        let watch = WatchSyncService.shared
        if watch.needsQualityChoice {
            guard let quality else { return .needsQuality }
            watch.setQuality(quality)
        }
        guard FeatureGate.shared.isAvailable(.downloads) else {
            return .failed("Downloads aren't available. Open Cue on your iPhone.")
        }
        let item = content(for: ref)
        guard watch.canAdd(item) else {
            return .failed("This can't go on your watch.")
        }
        let count = await watch.add(item)
        return count > 0 ? .added(songs: count) : .failed("Couldn't get its songs from your server. Check Cue on your iPhone can play it.")
    }
}

extension WatchSource {
    init?(_ service: MusicService) {
        switch service {
        case .plex: self = .plex
        case .subsonic: self = .subsonic
        default: return nil
        }
    }

    var service: MusicService {
        switch self {
        case .plex: .plex
        case .subsonic: .subsonic
        }
    }
}
