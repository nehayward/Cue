import Foundation
import OrderedCollections
import MusicKit
import MusicSearchKit


@Observable
public final class PlexBrowseService {
    public static var shared = PlexBrowseService()
    @ObservationIgnored private let plexAPI = PlexAPI.shared

    public var userAlbums: OrderedSet<PlayableContent> = []
    public var userPlaylists: OrderedSet<PlayableContent> = []
    /// The library's collections, as many pages as have been asked for.
    public var collections: OrderedSet<PlayableContent> = []
    /// How many collections the library holds; nil until the server has said.
    public var collectionCount: Int?

    /// Items asked of the server per page of a collection.
    private let collectionPageSize = 100

    public init() { }

    /// Loads a page of the library's collections. The first page replaces
    /// the list rather than merging into it, so a collection deleted on the
    /// server goes; a page that fails leaves the list as it was.
    public func updateCollections(offset: Int? = 0) async {
        let offset = offset ?? 0
        guard let page = await plexAPI.collections(offset: offset) else { return }
        let loaded = page.collections.map(\.toPlayable)
        if offset == 0 {
            collections = OrderedSet(loaded)
        } else {
            collections.append(contentsOf: loaded)
        }
        collectionCount = page.total ?? collections.count
        await checkCollectionAccess()
    }

    /// Everything `collection` holds, in `order` (see
    /// `inCollectionOrder`): the server keeps a collection's items in the
    /// order they were placed whatever its sort, so the whole collection is
    /// read and put in order here. Nil when it couldn't load; a page after
    /// the first that fails ends the list there.
    public func items(of collection: PlayableContent, in order: PlexCollectionSort, limit: Int = 1_000) async -> [PlayableContent]? {
        guard let key = ratingKey(of: collection) else { return nil }
        var metadata: [PlexMetadata] = []
        var offset = 0
        while offset < limit {
            guard let page = await plexAPI.collectionItems(ratingKey: key, offset: offset, limit: collectionPageSize) else {
                if offset == 0 { return nil }
                break
            }
            metadata += page.items
            // A full page on, not after the items read: one that didn't
            // decode drops out of `items`, and counting from those would ask
            // for rows already read.
            offset += collectionPageSize
            let hasMore = page.total.map { offset < $0 } ?? (page.items.count == collectionPageSize)
            guard hasMore else { break }
        }
        // A music collection holds albums, artists or songs; anything else
        // has no content type, which `toPlayable` can't map.
        return metadata
            .filter { ContentType($0.type) != nil }
            .inCollectionOrder(order)
            .map(\.toPlayable)
    }

    /// Everything `collection` holds, in the order it's kept in, for playing
    /// it from the top.
    public func allCollectionItems(of collection: PlayableContent) async -> [PlayableContent] {
        let order = await details(of: collection)?.sortOrder ?? .releaseDate
        return await items(of: collection, in: order) ?? []
    }

    // MARK: - Managing collections

    /// Whether the signed-in account can change the library's collections:
    /// only the server's owner can. Nil until checked, which happens
    /// whenever collections load.
    public var canManageCollections: Bool?

    /// Checks `canManageCollections` against the server.
    @discardableResult
    public func checkCollectionAccess() async -> Bool {
        let owns = await plexAPI.ownsServer()
        canManageCollections = owns
        return owns
    }

    /// The collection as the server has it now: its title after a rename,
    /// whether it's smart, and the order it's kept in.
    public func details(of collection: PlayableContent) async -> PlexCollection? {
        guard let key = ratingKey(of: collection) else { return nil }
        return await plexAPI.collection(ratingKey: key)
    }

    /// The collections `item` can go into, for the Add to Collection list:
    /// every hand-made collection holding its kind of item. Smart ones are
    /// saved filters, with nothing to add to. Nil when they couldn't load.
    public func collections(accepting item: PlayableContent, limit: Int = 1_000) async -> [PlayableContent]? {
        guard let subtype = Self.collectionSubtype(for: item.content.type) else { return [] }
        var accepted: [PlayableContent] = []
        var offset = 0
        while offset < limit {
            guard let page = await plexAPI.collections(offset: offset) else {
                return offset == 0 ? nil : accepted
            }
            accepted += page.collections
                .filter { !$0.smart && $0.subtype == subtype }
                .map(\.toPlayable)
            offset += page.collections.count
            guard !page.collections.isEmpty, offset < (page.total ?? 0) else { break }
        }
        return accepted
    }

    /// Makes a collection named `title` holding `item`. The new collection,
    /// or nil if it couldn't be made.
    public func createCollection(named title: String, with item: PlayableContent) async -> PlayableContent? {
        guard let itemKey = ratingKey(of: item),
              let type = Self.collectionMediaType(for: item.content.type),
              let key = await plexAPI.createCollection(title: title, itemRatingKey: itemKey, type: type)
        else { return nil }
        await updateCollections()
        // Read back with its artwork; failing that, enough to open it by.
        return await plexAPI.collection(ratingKey: key)?.toPlayable
            ?? collections.first { ratingKey(of: $0) == key }
            ?? PlayableContent(
                title: title,
                subtitle: "",
                thumbnail: nil,
                artwork: nil,
                content: .init(service: .plex, id: key, type: .folder, location: nil)
            )
    }

    public func add(_ item: PlayableContent, to collection: PlayableContent) async -> Bool {
        guard let key = ratingKey(of: collection), let itemKey = ratingKey(of: item),
              await plexAPI.addToCollection(collectionRatingKey: key, itemRatingKey: itemKey)
        else { return false }
        await updateCollections()
        return true
    }

    public func remove(_ item: PlayableContent, from collection: PlayableContent) async -> Bool {
        guard let key = ratingKey(of: collection), let itemKey = ratingKey(of: item),
              await plexAPI.removeFromCollection(collectionRatingKey: key, itemRatingKey: itemKey)
        else { return false }
        await updateCollections()
        return true
    }

    public func rename(_ collection: PlayableContent, to title: String) async -> Bool {
        guard let key = ratingKey(of: collection),
              await plexAPI.renameCollection(ratingKey: key, title: title)
        else { return false }
        await updateCollections()
        return true
    }

    public func delete(_ collection: PlayableContent) async -> Bool {
        guard let key = ratingKey(of: collection),
              await plexAPI.deleteCollection(ratingKey: key)
        else { return false }
        await updateCollections()
        return true
    }

    /// Sets the order `collection` is kept in. Its items can only be moved
    /// in `.custom`.
    public func setOrder(_ sort: PlexCollectionSort, for collection: PlayableContent) async -> Bool {
        guard let key = ratingKey(of: collection) else { return false }
        return await plexAPI.setCollectionSort(ratingKey: key, sort: sort)
    }

    /// Moves `item` to just after `previous` in a custom-ordered collection,
    /// or to the front when `previous` is nil.
    public func move(_ item: PlayableContent, after previous: PlayableContent?, in collection: PlayableContent) async -> Bool {
        guard let key = ratingKey(of: collection), let itemKey = ratingKey(of: item) else { return false }
        let previousKey = previous.flatMap { ratingKey(of: $0) }
        return await plexAPI.moveCollectionItem(collectionRatingKey: key, itemRatingKey: itemKey, afterItemRatingKey: previousKey)
    }

    /// A Plex item's ratingKey, the last part of the id Cue keys it by.
    private func ratingKey(of content: PlayableContent) -> String? {
        content.id.removingPercentEncoding?.components(separatedBy: ":").last
    }

    /// The `subtype` of a collection that holds `type`.
    private static func collectionSubtype(for type: ContentType) -> String? {
        switch type {
        case .album: "album"
        case .artist: "artist"
        case .track: "track"
        default: nil
        }
    }

    private static func collectionMediaType(for type: ContentType) -> PlexMediaType? {
        switch type {
        case .album: .album
        case .artist: .artist
        case .track: .song
        default: nil
        }
    }

    public func updateUserPlaylists(offset: Int? = 0) async {
        // Merge in the server's playlists (additive) so a just-created playlist is never dropped —
        // Plex can briefly omit a brand-new empty playlist from this list. Deletions are reflected
        // explicitly by the delete flow (`removeUserPlaylist`), not by clearing here.
        for playlist in await plexAPI.playlists().map(\.toPlayable) {
            userPlaylists.updateOrAppend(playlist)
        }
    }
    
    public func artists(offset: Int? = 0) async -> [PlayableContent]  {
        let artists = await plexAPI.artists(offset: offset ?? 0)
        return artists.compactMap(\.toPlayable)
    }
    
    /// A page of albums in the requested order. As with songs, Plex sorts on
    /// the server, so the order (reversed included) holds across every page.
    public func updateUserAlbums(offset: Int? = 0, sort: PlexAlbumSort = .title, reversed: Bool = false) async -> [PlayableContent]  {
        let albums = await plexAPI.albums(sort: sort, reversed: reversed, offset: offset ?? 0)
        let newUserAlbums = albums.compactMap(\.toPlayable)
        return newUserAlbums
    }
    
    /// A page of songs in the requested order. Plex sorts on the server, so
    /// there is nothing to sync and nothing to re-sort — the order (reversed
    /// included) holds across every page.
    public func songs(offset: Int? = 0, sort: PlexSongSort = .title, reversed: Bool = false) async -> [PlayableContent]  {
        let songs = await plexAPI.songs(sort: sort, reversed: reversed, offset: offset ?? 0)
        return songs.compactMap(\.toPlayable)
    }
}

