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
    /// account's country, else the device's region. Kept once read.
    private static var knownStorefront: String?

    static func storefront() async -> String {
        if let knownStorefront { return knownStorefront }
        if let code = try? await MusicDataRequest.currentCountryCode {
            knownStorefront = code.lowercased()
            return code.lowercased()
        }
        return (Locale.current.region?.identifier ?? "us").lowercased()
    }
}
