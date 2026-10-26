import Foundation
import MusicKit

/// An Apple Music album's moving cover: the short looping video Apple Music
/// plays in place of the still, which the Apple Music API lists as the
/// album's `editorialVideo`. Most albums have none. Each shape is an HLS
/// stream with no sound.
public struct AppleMotionArtwork: Codable, Hashable, Sendable {
    /// For a square cover: the player's, an album page's.
    public let square: URL?
    /// 3:4, for a frame taller than it is wide.
    public let tall: URL?

    public init(square: URL?, tall: URL?) {
        self.square = square
        self.tall = tall
    }

    /// The square video, else the tall one (cropped by whoever draws it),
    /// or the other way round.
    public func video(tall prefersTall: Bool) -> URL? {
        prefersTall ? tall ?? square : square ?? tall
    }

    /// The shapes picked out of `editorialVideo`'s videos by name, nil when
    /// there's neither. Apple names each by where its own app shows it
    /// (`motionDetailSquare` on an album's page, `motionSquareVideo1x1` in a
    /// grid, and their tall twins): the page's come first, then any name
    /// that says its shape.
    public init?(videos: [String: URL]) {
        func pick(_ names: [String], shape: [String]) -> URL? {
            if let name = names.first(where: { videos[$0] != nil }) { return videos[name] }
            let named = videos.keys.sorted().first { name in
                shape.contains { name.localizedCaseInsensitiveContains($0) }
            }
            return named.flatMap { videos[$0] }
        }
        let square = pick(["motionDetailSquare", "motionSquareVideo1x1"], shape: ["square", "1x1"])
        let tall = pick(["motionDetailTall", "motionTallVideo3x4"], shape: ["tall", "3x4"])
        guard square != nil || tall != nil else { return nil }
        self.init(square: square, tall: tall)
    }

    /// The videos an Apple Music API album response lists under its first
    /// album's `editorialVideo`, by shape name. Nil when the album came back
    /// with no `editorialVideo` at all, which is what tells "Apple didn't
    /// send it" from "this album's has no video" in the log; empty when it
    /// named shapes without a video.
    public static func editorialVideos(inAlbumResponse data: Data) throws -> [String: URL]? {
        let response = try JSONDecoder().decode(AlbumResponse.self, from: data)
        guard let videos = response.data.first?.attributes?.editorialVideo else { return nil }
        return videos.compactMapValues(\.video)
    }

    /// The videos an album's page on music.apple.com shows in its header, by
    /// shape name, read from the JSON the page carries for its own script
    /// (`<script id="serialized-server-data">`). The website shows anyone an
    /// album's moving cover, signed in or not, though the API keeps it from
    /// Cue: the header item's `videoArtwork` holds the square and
    /// `tallVideoArtwork` the tall, named as `editorialVideo`'s are. Empty
    /// for an album whose page has no video; nil when the page isn't laid out
    /// as expected (no data, no sections), so a change on Apple's side shows
    /// in the log rather than passing for albums without videos.
    public static func editorialVideos(inAlbumPage page: Data) throws -> [String: URL]? {
        guard let json = serializedServerData(in: page) else { return nil }
        let sections = try JSONDecoder().decode(AlbumPage.self, from: json).data
            .flatMap { $0.data?.sections ?? [] }
            .compactMap(\.value)
        guard let header = sections.first(where: { $0.itemKind == "containerDetailHeaderLockup" }) ?? sections.first else { return nil }
        var videos: [String: URL] = [:]
        for item in (header.items ?? []).compactMap(\.value) {
            for artwork in [item.videoArtwork, item.tallVideoArtwork] {
                for (shape, video) in artwork?.dictionary ?? [:] {
                    if let url = video.video { videos[shape] = url }
                }
            }
        }
        return videos
    }

    /// The JSON inside the page's `serialized-server-data` script.
    private static func serializedServerData(in page: Data) -> Data? {
        guard let marker = page.range(of: Data(#"id="serialized-server-data""#.utf8)),
              let open = page.range(of: Data(">".utf8), in: marker.upperBound..<page.endIndex),
              let close = page.range(of: Data("</script>".utf8), in: open.upperBound..<page.endIndex) else { return nil }
        return page.subdata(in: open.upperBound..<close.lowerBound)
    }

    private struct AlbumPage: Decodable {
        let data: [Intent]

        struct Intent: Decodable {
            let data: Content?
        }

        struct Content: Decodable {
            let sections: [Lenient<Section>]?
        }

        struct Section: Decodable {
            let itemKind: String?
            let items: [Lenient<Item>]?
        }

        struct Item: Decodable {
            let videoArtwork: VideoArtwork?
            let tallVideoArtwork: VideoArtwork?
        }

        struct VideoArtwork: Decodable {
            let dictionary: [String: Shape]?
        }
    }

    /// A value read if it can be, else nil, so one section or item that
    /// isn't what's expected doesn't lose the page.
    private struct Lenient<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    private struct AlbumResponse: Decodable {
        let data: [Resource]
    }

    private struct Resource: Decodable {
        let attributes: Attributes?
    }

    private struct Attributes: Decodable {
        let editorialVideo: [String: Shape]?
    }

    /// One shape: its `video`, beside a `previewFrame` still Cue doesn't
    /// need. Read leniently, so one shape that isn't what's expected doesn't
    /// lose the others.
    private struct Shape: Decodable {
        let video: URL?

        enum CodingKeys: String, CodingKey {
            case video
        }

        init(from decoder: Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            let string = try? container?.decodeIfPresent(String.self, forKey: .video)
            video = string.flatMap { URL(string: $0) }
        }
    }
}

extension AppleMusicAPI {
    /// The videos the catalog album `id` lists under `editorialVideo` (see
    /// `AppleMotionArtwork.editorialVideos(inAlbumResponse:)`). Like the
    /// other lookups here it needs Apple Music allowed, but it never asks:
    /// the caller checks first, so a cover never puts up the prompt.
    public func editorialVideos(albumID: String) async throws -> [String: URL]? {
        let storefront = await Self.storefront()
        guard var components = URLComponents(string: "https://api.music.apple.com/v1/catalog/\(storefront)/albums/\(albumID)") else { return nil }
        components.queryItems = [URLQueryItem(name: "extend", value: "editorialVideo")]
        guard let url = components.url else { return nil }
        let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
        return try AppleMotionArtwork.editorialVideos(inAlbumResponse: response.data)
    }

    /// The videos the catalog album `id`'s page on music.apple.com shows, in
    /// the listener's storefront (see
    /// `AppleMotionArtwork.editorialVideos(inAlbumPage:)`). The public page,
    /// so it needs no sign-in; about half a megabyte a page.
    public func albumPageVideos(albumID: String) async throws -> [String: URL]? {
        let storefront = await Self.storefront()
        guard let url = URL(string: "https://music.apple.com/\(storefront)/album/\(albumID)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try AppleMotionArtwork.editorialVideos(inAlbumPage: data)
    }

    /// The catalog album the song `id` is on: a catalog song's, or a library
    /// song's (`i.…`) by its catalog twin. Nil when it has none (an upload).
    public func catalogAlbumID(forSong id: String) async throws -> String? {
        var songID = id
        if id.hasPrefix("i.") {
            guard let catalogID = try await firstID(at: "https://api.music.apple.com/v1/me/library/songs/\(id)/catalog") else { return nil }
            songID = catalogID
        }
        let storefront = await Self.storefront()
        return try await firstID(at: "https://api.music.apple.com/v1/catalog/\(storefront)/songs/\(songID)/albums")
    }

    /// The catalog twin of the library album `id` (`l.…`), nil when it has
    /// none.
    public func catalogAlbumID(forLibraryAlbum id: String) async throws -> String? {
        try await firstID(at: "https://api.music.apple.com/v1/me/library/albums/\(id)/catalog")
    }

    /// The id of the first resource the Apple Music API lists at `address`.
    private func firstID(at address: String) async throws -> String? {
        guard let url = URL(string: address) else { return nil }
        let response = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response()
        struct Listing: Decodable {
            struct Resource: Decodable { let id: String }
            let data: [Resource]
        }
        return try JSONDecoder().decode(Listing.self, from: response.data).data.first?.id
    }

    /// The listener's storefront, which the catalog is read in: their
    /// account's country, else the device's region. Kept once read, behind
    /// a lock, since lookups run side by side.
    private static var knownStorefront: String?
    private static let storefrontLock = NSLock()

    static func storefront() async -> String {
        if let known = storefrontLock.withLock({ knownStorefront }) { return known }
        if let code = try? await MusicDataRequest.currentCountryCode {
            let storefront = code.lowercased()
            storefrontLock.withLock { knownStorefront = storefront }
            return storefront
        }
        return (Locale.current.region?.identifier ?? "us").lowercased()
    }
}
