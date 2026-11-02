import Defaults
import Foundation
import UIKit

/// Apple Music's artists and their releases, from Apple's public iTunes
/// Search service and the artist's Apple Music page (for the photo), which
/// need no sign-in, so the widget reads them itself: an artist's new
/// release reaches the widget without Cue running. The ids are Apple
/// Music's, which Cue plays (`apple|<id>`).
enum AppleMusicArtists {
    static let prefix = "apple|"
    /// How long a reading stands before the widget reads the artist again.
    static let refreshAfter: TimeInterval = 6 * 3600
    /// The covers fetched: more than the widest widget shows.
    private static let coverCount = 24

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }()

    /// The storefront Cue wrote for the album shelf, else the device's
    /// region; read once, as the catalog is a large file.
    private static let storefront: String = BookShelfWidgetState.Catalog.load(.albums)?.storefront
        ?? Locale.current.region?.identifier.lowercased()
        ?? "us"

    private struct Response: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let wrapperType: String?
        let artistId: Int?
        let artistName: String?
        let artistLinkUrl: String?
        let primaryGenreName: String?
        let collectionId: Int?
        let collectionName: String?
        let collectionExplicitness: String?
        let releaseDate: String?
        let artworkUrl100: String?
    }

    private static func results(path: String, items: [URLQueryItem]) async -> [Result]? {
        guard var components = URLComponents(string: "https://itunes.apple.com/\(path)") else { return nil }
        components.queryItems = items + [URLQueryItem(name: "country", value: storefront)]
        guard let url = components.url,
              let (data, _) = try? await session.data(from: url),
              let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return response.results
    }

    // MARK: - Artists

    /// The artists a search finds, the first few with their photos.
    static func search(_ query: String) async -> [WidgetArtist] {
        let results = await results(path: "search", items: [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "musicArtist"),
            URLQueryItem(name: "limit", value: "25"),
        ]) ?? []
        let found = results.compactMap { result -> (artist: WidgetArtist, page: URL?)? in
            guard result.wrapperType == "artist", let id = result.artistId, let name = result.artistName else { return nil }
            return (WidgetArtist(id: "\(prefix)\(id)", name: name, detail: result.primaryGenreName ?? ""), result.artistLinkUrl.flatMap(URL.init(string:)))
        }
        let photos = await photoURLs(for: found.prefix(photosInSearch).compactMap { found in found.page.map { (found.artist.id, $0) } })
        return found.map { found in
            var artist = found.artist
            artist.photoURL = photos[artist.id]
            return artist
        }
    }

    /// The search results given photos: the rest of a long list is scrolled
    /// to rarely, and each is a page to read.
    private static let photosInSearch = 8

    /// Each artist's photo, from the ones read before (kept in the App
    /// Group, an artist whose page has none as "", so it isn't read again)
    /// or read now from their pages, all at once.
    private static func photoURLs(for artists: [(id: String, page: URL)]) async -> [String: URL] {
        let file = DiscographyArtist.directory?.appendingPathComponent("ArtistPhotos.json")
        var known = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        let missing = artists.filter { known[$0.id] == nil }
        if !missing.isEmpty {
            let read = await withTaskGroup(of: (String, PagePhoto).self) { group in
                for (id, page) in missing {
                    group.addTask { (id, await photo(page: page)) }
                }
                var read: [String: String] = [:]
                for await (id, photo) in group {
                    switch photo {
                    case .found(let url): read[id] = url.absoluteString
                    case .missing: read[id] = ""
                    case .unread: break
                    }
                }
                return read
            }
            if !read.isEmpty {
                known.merge(read) { _, new in new }
                if let file, let directory = DiscographyArtist.directory, let data = try? JSONEncoder().encode(known) {
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try? data.write(to: file, options: .atomic)
                }
            }
        }
        return known.compactMapValues(URL.init(string:))
    }

    /// The artist of an Apple Music album, by its key (`apple|<catalog
    /// id>`; a library album's isn't one the catalog knows).
    static func artistID(ofAlbum albumID: String) async -> String? {
        let number = String(albumID.dropFirst(prefix.count))
        guard albumID.hasPrefix(prefix), !number.isEmpty, number.allSatisfy(\.isNumber),
              let result = await results(path: "lookup", items: [URLQueryItem(name: "id", value: number)])?.first,
              let artistID = result.artistId else { return nil }
        return "\(prefix)\(artistID)"
    }

    /// The artist an id names, for an Edit Widget choice Cue hasn't read yet.
    static func artist(named id: String) async -> WidgetArtist? {
        let results = await results(path: "lookup", items: [URLQueryItem(name: "id", value: String(id.dropFirst(prefix.count)))])
        guard let result = results?.first(where: { $0.wrapperType == "artist" }), let name = result.artistName else { return nil }
        return WidgetArtist(id: id, name: name, detail: result.primaryGenreName ?? "")
    }

    // MARK: - Releases

    /// The artist as last read, read again once it's older than
    /// `refreshAfter`: their releases, the covers the newest of them have
    /// no file for yet, and their photo the first time. What was read
    /// before stands when the catalog doesn't answer.
    static func discography(of id: String) async -> DiscographyArtist? {
        let kept = DiscographyArtist.load(id: id)
        if let kept, Date.now.timeIntervalSince(kept.readAt) < refreshAfter { return kept }
        guard let results = await results(path: "lookup", items: [
            URLQueryItem(name: "id", value: String(id.dropFirst(prefix.count))),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "200"),
        ]), let artist = results.first(where: { $0.wrapperType == "artist" }), let name = artist.artistName else { return kept }
        guard let directory = DiscographyArtist.directory else { return kept }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let releases = Self.releases(in: results, by: name)
        // The newest, and any written before, found by name (a widget
        // writes those it shows, `writeCovers`, which can be far down).
        let covers = await download(releases.enumerated().compactMap { index, release in
            guard let artwork = release.artwork, index < coverCount || isWritten(artwork, for: id) else { return nil }
            return (release.id, artwork)
        }, for: id)
        var photo = kept?.photo.flatMap { name in
            DiscographyArtist.imageURL(named: name).map { FileManager.default.fileExists(atPath: $0.path) } == true ? name : nil
        }
        if photo == nil, let page = artist.artistLinkUrl.flatMap(URL.init(string:)), let source = await photoURLs(for: [(id, page)])[id] {
            photo = await download([(id, source)], for: id)[id]
        }
        let read = DiscographyArtist(
            id: id,
            name: name,
            photo: photo,
            releases: releases.map { .init(id: $0.id, title: $0.title, released: $0.released, cover: covers[$0.id], artwork: $0.artwork) },
            readAt: .now
        )
        try? read.save()
        return read
    }

    private struct Found {
        let id: String
        let title: String
        let released: Date?
        let artwork: URL?
    }

    /// Writes the covers of `ids` the artist has none for yet, and keeps
    /// them: the releases a widget shows, which for Studio Albums can be far
    /// past the newest the read fetched.
    static func writeCovers(of artist: DiscographyArtist, for ids: Set<String>) async -> DiscographyArtist {
        let missing = artist.releases.compactMap { release -> (id: String, source: URL)? in
            guard ids.contains(release.id), release.cover == nil, let artwork = release.artwork else { return nil }
            return (release.id, artwork)
        }
        guard !missing.isEmpty else { return artist }
        let names = await download(missing, for: artist.id)
        guard !names.isEmpty else { return artist }
        var written = artist
        for index in written.releases.indices {
            if let name = names[written.releases[index].id] {
                written.releases[index].cover = name
            }
        }
        try? written.save()
        return written
    }

    /// Every release but singles and the clean copy of an album that has an
    /// explicit one, newest first. Remix albums and second listings stay
    /// for Apple's album list to name; All Releases leaves them out as it
    /// shows them (`everyRelease()`).
    private static func releases(in results: [Result], by artist: String) -> [Found] {
        let dates = ISO8601DateFormatter()
        return results
            .compactMap { result -> Found? in
                guard result.wrapperType == "collection", result.collectionExplicitness != "cleaned",
                      let id = result.collectionId, let title = result.collectionName, !title.hasSuffix(" - Single") else { return nil }
                // The 100 px cover, asked for at 300 px: crisp at the
                // widest grid's size on a 3x screen.
                let artwork = result.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "300x300bb")) }
                return Found(id: "\(prefix)\(id)", title: shortTitle(title, by: artist), released: result.releaseDate.flatMap(dates.date(from:)), artwork: artwork)
            }
            .sorted { ($0.released ?? .distantPast) > ($1.released ?? .distantPast) }
    }

    private static func isWritten(_ artwork: URL, for artistID: String) -> Bool {
        DiscographyArtist.imageURL(named: DiscographyArtist.imageName(for: artistID, source: artwork.absoluteString))
            .map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// The title as the widget names it, under the artist's own name:
    /// "Dua Lipa - Live From Mexico" is "Live From Mexico", and "Training
    /// Season's Over - EP" is "Training Season's Over EP".
    private static func shortTitle(_ title: String, by artist: String) -> String {
        var title = title
        if title.hasSuffix(" - EP") {
            title = String(title.dropLast(5)) + " EP"
        }
        let byline = "\(artist) - "
        if title.count > byline.count, title.lowercased().hasPrefix(byline.lowercased()) {
            title = String(title.dropFirst(byline.count))
        }
        return title
    }

    private enum PagePhoto {
        case found(URL)
        /// The page was read and has no photo.
        case missing
        /// The page wasn't read.
        case unread
    }

    /// The square photo from the artist's Apple Music page (its `og:image`,
    /// a wide social card, asked for square). Read only as far as the tag,
    /// a few KB into the page's head: the whole page is some 800 KB.
    private static func photo(page: URL) async -> PagePhoto {
        var components = URLComponents(url: page, resolvingAgainstBaseURL: false)
        components?.query = nil
        guard let url = components?.url else { return .unread }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        guard let (bytes, response) = try? await session.bytes(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return .unread }
        var head = Data()
        do {
            for try await byte in bytes {
                head.append(byte)
                if head.count.isMultiple(of: 1024), let image = imageURL(in: head) { return .found(image) }
                if head.count >= 64 * 1024 { break }
            }
        } catch {
            return imageURL(in: head).map(PagePhoto.found) ?? .unread
        }
        return imageURL(in: head).map(PagePhoto.found) ?? .missing
    }

    private static func imageURL(in head: Data) -> URL? {
        let html = String(decoding: head, as: UTF8.self)
        guard let start = html.range(of: #"property="og:image" content=""#)?.upperBound,
              let end = html[start...].firstIndex(of: "\""),
              var image = URL(string: String(html[start..<end])), image.host()?.contains("mzstatic.com") == true else { return nil }
        image.deleteLastPathComponent()
        return image.appending(path: "300x300cc.jpg")
    }

    /// Fetches the images not written yet, each to a file named for the
    /// artist and its source, at once; the file names by item.
    private static func download(_ items: [(id: String, source: URL)], for artistID: String) async -> [String: String] {
        await withTaskGroup(of: (String, String?).self) { group in
            for (itemID, source) in items {
                group.addTask {
                    let name = DiscographyArtist.imageName(for: artistID, source: source.absoluteString)
                    guard let file = DiscographyArtist.imageURL(named: name) else { return (itemID, nil) }
                    if FileManager.default.fileExists(atPath: file.path) { return (itemID, name) }
                    guard let (data, response) = try? await session.data(from: source),
                          (response as? HTTPURLResponse)?.statusCode == 200, UIImage(data: data) != nil,
                          (try? data.write(to: file, options: .atomic)) != nil else { return (itemID, nil) }
                    return (itemID, name)
                }
            }
            var names: [String: String] = [:]
            for await (itemID, name) in group {
                names[itemID] = name
            }
            return names
        }
    }
}
