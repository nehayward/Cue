import Foundation

// Audiobookshelf's JSON, as its server sends it (v2.17 and later; checked
// against v2.37). Everything is optional that a server of some version, or
// an item of some kind, can leave out: an ebook-only item has no tracks, a
// podcast no author, a book never started no progress.

/// `POST /login` and `POST /auth/refresh`.
public struct AudiobookshelfLoginResponse: Decodable, Sendable {
    public let user: AudiobookshelfUser
    public let userDefaultLibraryId: String?
}

public struct AudiobookshelfUser: Decodable, Sendable {
    public let id: String
    public let username: String?
    /// The token servers before 2.26 hand out, which never expires. Newer
    /// servers still send it, deprecated.
    public let token: String?
    /// 2.26 and later: an access token lasting an hour (twelve before
    /// 2.31), and the refresh token that renews it. The refresh token is in
    /// the body only when asked for (`x-return-tokens: true`).
    public let accessToken: String?
    public let refreshToken: String?
    public let mediaProgress: [AudiobookshelfMediaProgress]?
}

/// `GET /status`: which ways in a server offers.
public struct AudiobookshelfStatus: Decodable, Sendable {
    public let app: String?
    public let serverVersion: String?
    /// `local` for a username and password; `openid` for single sign-on.
    public let authMethods: [String]?
    public let authFormData: AuthFormData?

    /// What the server's own sign-in page says.
    public struct AuthFormData: Decodable, Sendable {
        /// The single sign-on button's title ("Login with Authentik").
        public let authOpenIDButtonText: String?
    }
}

public struct AudiobookshelfLibrariesResponse: Decodable, Sendable {
    public let libraries: [AudiobookshelfLibrary]
}

public struct AudiobookshelfLibrary: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    /// `book` or `podcast`.
    public let mediaType: String?

    public var isBooks: Bool { (mediaType ?? "book") == "book" }
}

/// `GET /api/libraries/<id>/items`: one page.
public struct AudiobookshelfItemsPage: Decodable, Sendable {
    public let results: [AudiobookshelfItem]
    public let total: Int?
}

/// `GET /api/me/items-in-progress`.
public struct AudiobookshelfInProgress: Decodable, Sendable {
    public let libraryItems: [AudiobookshelfItem]
}

/// `GET /api/libraries/<id>/search`.
public struct AudiobookshelfSearchResult: Decodable, Sendable {
    public struct Match: Decodable, Sendable {
        public let libraryItem: AudiobookshelfItem
    }
    /// Books matched by their title (an author's name finds the author,
    /// not their books).
    public let book: [Match]?
    public let authors: [AudiobookshelfAuthor]?
}

/// An author in a library: their name and picture, and with
/// `include=items`, their books.
public struct AudiobookshelfAuthor: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    /// Where the server keeps their picture; nil for none.
    public let imagePath: String?
    public let libraryItems: [AudiobookshelfItem]?
}

/// A library item: a book (or a podcast, which Cue leaves out).
public struct AudiobookshelfItem: Decodable, Sendable, Identifiable {
    public let id: String
    public let libraryId: String?
    public let mediaType: String?
    /// Milliseconds since 1970.
    public let addedAt: Int64?
    public let media: AudiobookshelfBookMedia?
    /// With `include=progress` on an item.
    public let userMediaProgress: AudiobookshelfMediaProgress?
    /// On items in progress: when the listener was last in it, ms.
    public let progressLastUpdate: Int64?
    /// The server's last scan didn't find the item's folder.
    public let isMissing: Bool?

    /// A book with something to listen to: ebook-only items have no tracks.
    public var hasAudio: Bool {
        (mediaType ?? "book") == "book" && (media?.numTracks ?? media?.tracks?.count ?? 1) > 0
    }
}

public struct AudiobookshelfBookMedia: Decodable, Sendable {
    public let duration: Double?
    public let numTracks: Int?
    public let numChapters: Int?
    public let metadata: AudiobookshelfBookMetadata?
    /// Expanded items only: chapters in book time, seconds.
    public let chapters: [AudiobookshelfChapter]?
    /// Expanded items only: the files to play, in order.
    public let tracks: [AudiobookshelfTrack]?
}

public struct AudiobookshelfBookMetadata: Decodable, Sendable {
    public let title: String?
    public let subtitle: String?
    public let authorName: String?
    public let narratorName: String?
    public let seriesName: String?
    public let description: String?
    public let publishedYear: String?
    /// Audible's id for the book, when it was matched there.
    public let asin: String?
}

public struct AudiobookshelfChapter: Decodable, Sendable {
    public let id: Int?
    public let start: Double
    public let end: Double
    public let title: String?
}

/// A file of a book, as the server plays it.
public struct AudiobookshelfTrack: Decodable, Sendable {
    /// Its number among the book's files, from one. Files left out of the
    /// book leave gaps; a listening session's track URLs go by this.
    public let index: Int
    /// Where it starts in the book, seconds.
    public let startOffset: Double?
    public let duration: Double
    public let title: String?
    /// `/api/items/<id>/file/<ino>` for a file played directly.
    public let contentUrl: String?
    public let mimeType: String?
    public let codec: String?
    public let ino: String?
    public let metadata: FileMetadata?

    public struct FileMetadata: Decodable, Sendable {
        public let filename: String?
        /// With its dot: ".m4b".
        public let ext: String?
    }

    /// The file's inode id, which its file URL names: given, or read off
    /// the content URL.
    public var fileID: String? {
        if let ino, !ino.isEmpty { return ino }
        guard let contentUrl, let range = contentUrl.range(of: "/file/") else { return nil }
        let rest = contentUrl[range.upperBound...]
        let id = rest.prefix { $0 != "/" && $0 != "?" }
        return id.isEmpty ? nil : String(id)
    }

    /// The file's extension, lowercased, without the dot.
    public var fileExtension: String? {
        let ext = metadata?.ext ?? metadata?.filename.flatMap { name in
            name.lastIndex(of: ".").map { String(name[$0...]) }
        }
        guard let ext else { return nil }
        let bare = ext.hasPrefix(".") ? String(ext.dropFirst()) : ext
        return bare.isEmpty ? nil : bare.lowercased()
    }
}

/// Where a listener is in an item.
public struct AudiobookshelfMediaProgress: Decodable, Sendable {
    public let libraryItemId: String?
    public let episodeId: String?
    /// Seconds into the whole book.
    public let currentTime: Double?
    public let duration: Double?
    public let progress: Double?
    public let isFinished: Bool?
    /// Milliseconds since 1970.
    public let lastUpdate: Int64?
}

/// `POST /api/items/<id>/play`: a listening session, whose track URLs
/// (`/public/session/<id>/track/<index>`) need no sign-in while it's open.
public struct AudiobookshelfSession: Decodable, Sendable {
    public let id: String
    public let libraryItemId: String?
    public let currentTime: Double?
    public let duration: Double?
    public let audioTracks: [AudiobookshelfTrack]?
    public let chapters: [AudiobookshelfChapter]?
}

/// What the server has running (`/api/tasks`): a library scan is one until
/// it's done.
struct AudiobookshelfTasks: Decodable, Sendable {
    struct Task: Decodable, Sendable {
        struct Detail: Decodable, Sendable {
            let libraryId: String?
        }

        /// "library-scan" for a scan.
        let action: String?
        let isFinished: Bool?
        let data: Detail?
    }

    let tasks: [Task]?
}

/// `GET /api/libraries/<id>/series`.
struct AudiobookshelfSeriesPage: Decodable, Sendable {
    let results: [AudiobookshelfSeries]
}

/// A series in a library, its books in their order in it.
public struct AudiobookshelfSeries: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let books: [AudiobookshelfItem]?
}

/// `GET /api/libraries/<id>/collections`.
struct AudiobookshelfCollectionsPage: Decodable, Sendable {
    let results: [AudiobookshelfCollection]
}

/// A collection someone on the server made: books in the order they put
/// them, from one library.
public struct AudiobookshelfCollection: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let books: [AudiobookshelfItem]?
}
