import Foundation

public struct AppleLibrarySearchContainer: Codable {
    public let results: AppleLibraryResults
    public let meta: AppleLibraryMeta
}

public struct AppleLibraryResults: Codable {
    public let libraryArtists: AppleLibraryArtists?
    public let libraryAlbums: AppleLibraryAlbums?
    public let librarySongs: AppleLibrarySongs?
    public let libraryPlaylists: AppleLibraryPlaylists?
    
    public enum CodingKeys: String, CodingKey {
        case libraryArtists = "library-artists"
        case libraryAlbums = "library-albums"
        case librarySongs = "library-songs"
        case libraryPlaylists = "library-playlists"
    }
}

public struct AppleLibraryArtists: Codable {
    public let href: String
    public let data: [AppleLibraryArtist]
}

public struct AppleLibraryArtist: Codable {
    public let id: String
    public let type: String
    public let href: String
    public let attributes: AppleLibraryArtistAttributes
}

public struct AppleLibraryArtistAttributes: Codable {
    public let name: String
    public let artwork: AppleLibraryArtwork?
}

public struct AppleLibraryAlbums: Codable {
    public let href: String
    public let data: [AppleLibraryAlbum]
}

// MARK: - Album
public struct AppleLibraryAlbum: Codable {
    public let id: String
    public let type: String
    public let href: String
    public let attributes: AppleLibraryAlbumAttributes
}

public struct AppleLibraryAlbumAttributes: Codable {
    public let trackCount: Int
    public let genreNames: [String]
    public let releaseDate: String?
    public let name: String
    public let artistName: String?
    public let artwork: AppleLibraryArtwork?
    public let dateAdded: String?
    public let playParams: AppleLibraryPlayParams
}

// MARK: - Song
public struct AppleLibrarySongs: Codable {
    public let href: String
    public let data: [AppleLibraryItem]
}

public struct AppleLibraryPlaylists: Codable {
    public let href: String
    public let data: [AppleLibraryPlaylist]
}

public struct AppleLibraryPlaylist: Codable {
    public let id: String
    public let type: String
    public let href: String
    public let attributes: AppleLibraryPlaylistAttributes
}

public struct AppleLibraryPlaylistAttributes: Codable {
    public let lastModifiedDate: String
    public let canEdit: Bool
    public let name: String
    public let isPublic: Bool
    public let artwork: AppleLibraryArtwork
    public let hasCatalog: Bool
    public let playParams: AppleLibraryPlayParams
    public let dateAdded: String
}

public struct AppleLibraryPlayParams: Codable {
    public let id: String
    public let kind: String
    public let isLibrary: Bool
    public let reporting: Bool?
    public let catalogId: String?
    public let reportingId: String?
    public let purchasedId: String?
}

public struct AppleLibraryMeta: Codable {
    public let results: AppleLibraryMetaResults
}

public struct AppleLibraryMetaResults: Codable {
    public let order: [String]
}
