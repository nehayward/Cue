import Foundation

/// Reads a public Spotify playlist or album without signing in to Spotify,
/// from the page Spotify serves to embed it in other sites. That page holds
/// the list as JSON (`__NEXT_DATA__`): each song's title, artists and length,
/// but no album and no ISRC, and a playlist's first 100 songs only. The
/// playlist's own page says how many it holds, so the shortfall can be told.
///
/// Cue doesn't play Spotify, so nothing else of Spotify's is needed: the
/// songs are found again on a service Cue plays.
public struct SpotifyPlaylistReader: Sendable {
    /// The embed page's limit on a playlist's songs.
    public static let embedLimit = 100

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func read(_ kind: PlaylistLink.Kind, id: String) async throws -> ImportedPlaylist {
        let html = try await page("https://open.spotify.com/embed/\(kind.rawValue)/\(id)")
        let entity = try Self.entity(in: html)
        let tracks = Self.tracks(of: entity, album: kind == .album ? entity.name : nil)
        guard !tracks.isEmpty else { throw PlaylistImportError.empty }

        // Only a list cut off at the limit can be missing songs, so only
        // then is the full page (half a megabyte) worth fetching.
        var total: Int?
        if kind == .playlist, tracks.count >= Self.embedLimit,
           let page = try? await page("https://open.spotify.com/playlist/\(id)") {
            total = OpenGraphScraper.metaContent(property: "music:song_count", in: page).flatMap { Int($0) }
        }

        return ImportedPlaylist(
            name: entity.name ?? entity.title ?? "Spotify Playlist",
            source: .spotify,
            artwork: entity.coverArt?.sources?.compactMap(\.url).first.flatMap(URL.init(string:)),
            tracks: tracks,
            totalCount: total.map { max($0, tracks.count) }
        )
    }

    /// Songs given one by one (Spotify's desktop app copies a selection as a
    /// list of song links), read a few at a time. Songs that can't be read
    /// are left out; `totalCount` tells how many there were.
    public func read(trackIDs: [String], name: String = "Spotify Songs") async throws -> ImportedPlaylist {
        let found = await withTaskGroup(of: (Int, ImportedTrack?).self) { group in
            var results: [Int: ImportedTrack] = [:]
            var next = 0
            func add() {
                guard next < trackIDs.count else { return }
                let index = next
                let id = trackIDs[index]
                group.addTask {
                    guard let html = try? await page("https://open.spotify.com/embed/track/\(id)"),
                          let entity = try? Self.entity(in: html) else { return (index, nil) }
                    return (index, Self.track(entity, index: index))
                }
                next += 1
            }
            for _ in 0..<4 { add() }
            for await (index, track) in group {
                results[index] = track
                add()
            }
            return results
        }
        let tracks = found.keys.sorted().compactMap { found[$0] }
        guard !tracks.isEmpty else { throw PlaylistImportError.unreachable }
        return ImportedPlaylist(name: name, source: .spotify, tracks: tracks, totalCount: trackIDs.count)
    }

    /// Where a `spotify.link` short link goes. They redirect, so the answer's
    /// address is usually the link; a page that sends the browser on with
    /// script instead still names it.
    public func resolve(shortLink: URL) async -> PlaylistLink? {
        var request = URLRequest(url: shortLink)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request) else { return nil }
        if let url = response.url, let link = PlaylistLink(url.absoluteString), link != .spotifyShortLink(url) {
            return link
        }
        guard let html = String(data: data, encoding: .utf8),
              let range = html.range(of: #"https://open\.spotify\.com/(playlist|album)/[A-Za-z0-9]{22}"#, options: .regularExpression) else { return nil }
        return PlaylistLink(String(html[range]))
    }

    // MARK: - Fetching

    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private func page(_ address: String) async throws -> String {
        guard let url = URL(string: address) else { throw PlaylistImportError.unsupported }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PlaylistImportError.unreachable
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw PlaylistImportError.notFound
        }
        guard let html = String(data: data, encoding: .utf8) else { throw PlaylistImportError.unreachable }
        return html
    }

    // MARK: - Parsing

    struct NextData: Decodable {
        struct Props: Decodable {
            let pageProps: PageProps
        }
        struct PageProps: Decodable {
            let state: State?
            let status: Int?
        }
        struct State: Decodable {
            let data: StateData?
        }
        struct StateData: Decodable {
            let entity: Entity?
        }
        let props: Props
    }

    struct Entity: Decodable {
        struct Cover: Decodable {
            struct Source: Decodable {
                let url: String?
            }
            let sources: [Source]?
        }
        struct Artist: Decodable {
            let name: String?
        }
        struct Item: Decodable {
            let uri: String?
            let title: String?
            /// The artists, joined by ", " with a no-break space — which a
            /// band's own comma ("Earth, Wind & Fire") doesn't have.
            let subtitle: String?
            /// Milliseconds.
            let duration: Double?
            let entityType: String?
        }
        let name: String?
        let title: String?
        let uri: String?
        let coverArt: Cover?
        let trackList: [Item]?
        /// A single song's embed lists its artists rather than a subtitle.
        let artists: [Artist]?
        let duration: Double?
    }

    static func entity(in html: String) throws -> Entity {
        guard let start = html.range(of: #"<script id="__NEXT_DATA__" type="application/json">"#),
              let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex),
              let data = String(html[start.upperBound..<end.lowerBound]).data(using: .utf8) else {
            throw PlaylistImportError.unreachable
        }
        let next: NextData
        do {
            next = try JSONDecoder().decode(NextData.self, from: data)
        } catch {
            throw PlaylistImportError.unreachable
        }
        guard let entity = next.props.pageProps.state?.data?.entity else {
            throw next.props.pageProps.status == 404 ? PlaylistImportError.notFound : PlaylistImportError.unreachable
        }
        return entity
    }

    static func tracks(of entity: Entity, album: String?) -> [ImportedTrack] {
        (entity.trackList ?? [])
            .filter { $0.entityType == nil || $0.entityType == "track" }
            .compactMap { item -> (title: String, item: Entity.Item)? in
                guard let title = item.title, !title.isEmpty else { return nil }
                return (title, item)
            }
            .enumerated()
            .map { index, song in
                ImportedTrack(
                    id: index,
                    title: song.title,
                    artists: splitArtists(song.item.subtitle ?? ""),
                    album: album,
                    duration: song.item.duration.map { $0 / 1000 },
                    sourceID: song.item.uri
                )
            }
    }

    static func track(_ entity: Entity, index: Int) -> ImportedTrack? {
        guard let title = entity.title ?? entity.name, !title.isEmpty else { return nil }
        return ImportedTrack(
            id: index,
            title: title,
            artists: (entity.artists ?? []).compactMap(\.name),
            duration: entity.duration.map { $0 / 1000 },
            sourceID: entity.uri
        )
    }

    static func splitArtists(_ subtitle: String) -> [String] {
        subtitle
            .components(separatedBy: ",\u{00A0}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
