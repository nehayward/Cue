import Foundation
import MusicKit
import MusicSearchKit

extension Int {
    /// "1 song" / "12 songs" for album row subtitles — the standard-vs-deluxe
    /// edition cue. Pluralized via automatic grammar agreement so wording
    /// (and any future localization) comes from the inflection engine. Nil
    /// for zero counts (a zero means the service didn't report one), so
    /// callers drop the component instead of rendering "0 songs".
    var songCountLabel: String? {
        guard self > 0 else { return nil }
        return String(AttributedString(localized: "^[\(self) song](inflect: true)").characters)
    }
}

extension PlayableContent {
    public var toRadio: PlayableContent {
        let type: ContentType = content.type == .artist ? .artistRadio : .songRadio
        let radioTitle = content.service == .deezer ? "Mix \(title)" : title
        let content = MediaContent(service: content.service, id: content.id + ".radio", type: type, location: nil)
        var metadata = metadata ?? PlayableContentMetadata()
        metadata.radioStation = true
        return PlayableContent(title: radioTitle, subtitle: radioTitle, thumbnail: thumbnail, artwork: artwork, content: content, metadata: metadata)
    }
}

extension Track {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: song,
            subtitle: [artist, album].filter({ !$0.isEmpty }).joined(separator: " • "),
            thumbnail: artworkURL,
            artwork: artworkURL,
            content: MediaContent(service: musicService, id: trackID.description, type: trackID.contains("i.") ? .libraryTrack : .track, location: metadata?.openInURL),
            metadata: PlayableContentMetadata(duration: Duration.seconds(duration), artist: artist, album: album, position: position)
        )
    }
}

// MARK: - Apple Music Mapping
extension Song {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: title,
            subtitle: artistName,
            thumbnail: artwork?.url(width: 100, height: 100),
            artwork: artwork?.url(width: 600, height: 600),
            content: MediaContent(service: .apple, id: id.description, type: .track, location: url),
            previewURL: previewAssets?.first?.url,
            metadata: PlayableContentMetadata(
                duration: duration.map { Duration.seconds($0) },
                artist: artistName,
                album: albumTitle,
                isrc: isrc,
                audioCodec: audioVariants?.first?.description,
                isPlayable: playParameters != nil,
                isExplicit: contentRating == .explicit
            )
        )
    }
}

extension MusicKit.Track {
    public var toPlayable: PlayableContent {
        let durationSeconds = duration.map { Duration.seconds($0) }

        var artworkURL = artwork?.url(width: 600, height: 600)
        var thumbnailURL = artwork?.url(width: 100, height: 100)

        let pattern = "https%3A%2F%2F[^&]+"
        let regex = try? NSRegularExpression(pattern: pattern)

        func processURL(_ url: URL?) -> URL? {
            guard let url = url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                  components.scheme?.lowercased() == "musickit",
                  let regex = regex else {
                return url
            }

            let nsString = url.absoluteString as NSString
            let range = NSRange(location: 0, length: nsString.length)
            
            guard let match = regex.firstMatch(in: url.absoluteString, range: range) else {
                return url
            }

            let encodedUrl = nsString.substring(with: match.range)
            return URL(string: encodedUrl.removingPercentEncoding ?? "")
        }

        artworkURL = processURL(artworkURL)
        thumbnailURL = processURL(thumbnailURL)

        let previewURL: URL?
        switch self {
        case .song(let song): previewURL = song.previewAssets?.first?.url
        default: previewURL = nil
        }

        return PlayableContent(
            title: title,
            subtitle: artistName,
            thumbnail: thumbnailURL,
            artwork: artworkURL,
            content: MediaContent(service: .apple, id: id.description, type: .track, location: url),
            previewURL: previewURL,
            metadata: PlayableContentMetadata(
                duration: durationSeconds,
                artist: artistName,
                album: albumTitle,
                isrc: isrc,
                audioCodec: nil,
                isPlayable: playParameters != nil,
                isExplicit: contentRating == .explicit
            )
        )
    }

    public var toPlayableLibraryTrack: PlayableContent {
        let durationSeconds = duration.map { Duration.seconds($0) }

        var artworkURL = artwork?.url(width: 600, height: 600)
        var thumbnailURL = artwork?.url(width: 100, height: 100)

        let pattern = "https%3A%2F%2F[^&]+"
        let regex = try? NSRegularExpression(pattern: pattern)

        func processURL(_ url: URL?) -> URL? {
            guard let url = url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                  components.scheme?.lowercased() == "musickit",
                  let regex = regex else {
                return url
            }

            let nsString = url.absoluteString as NSString
            let range = NSRange(location: 0, length: nsString.length)
            
            guard let match = regex.firstMatch(in: url.absoluteString, range: range) else {
                return url
            }

            let encodedUrl = nsString.substring(with: match.range)
            return URL(string: encodedUrl.removingPercentEncoding ?? "")
        }

        artworkURL = processURL(artworkURL)
        thumbnailURL = processURL(thumbnailURL)

        return PlayableContent(
            title: title,
            subtitle: artistName,
            thumbnail: thumbnailURL,
            artwork: artworkURL,
            content: MediaContent(service: .apple, id: id.description, type: .libraryTrack, location: url),
            metadata: PlayableContentMetadata(
                duration: durationSeconds,
                artist: artistName,
                album: albumTitle,
                isrc: isrc,
                isPlayable: playParameters != nil
            )
        )
    }
}

extension Playlist {
    public func toPlayable(isUserPlaylist: Bool = false) ->  PlayableContent {
        var artworkURL = artwork?.url(width: 600, height: 600)
        var thumbnailURL = artwork?.url(width: 100, height: 100)

        let pattern = "https%3A%2F%2F[^&]+"
        let regex = try? NSRegularExpression(pattern: pattern)

        func processURL(_ url: URL?) -> URL? {
            guard let url = url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                  components.scheme?.lowercased() == "musickit",
                  let regex = regex else {
                return url
            }

            let nsString = url.absoluteString as NSString
            let range = NSRange(location: 0, length: nsString.length)
            
            guard let match = regex.firstMatch(in: url.absoluteString, range: range) else {
                return url
            }

            let encodedUrl = nsString.substring(with: match.range)
            return URL(string: encodedUrl.removingPercentEncoding ?? "")
        }

        artworkURL = processURL(artworkURL)
        thumbnailURL = processURL(thumbnailURL)

        return PlayableContent(
            title: name,
            subtitle: curatorName ?? "",
            thumbnail: thumbnailURL,
            artwork: artworkURL,
            content: MediaContent(
                service: .apple,
                id: id.description,
                type: isUserPlaylist ? .libraryPlaylist : .playlist,
                location: url
            ),
            metadata: .init(
                artist: self.featuredArtists?.first?.name
            )
        )
    }
}

extension AppleLibraryPlaylist {
    public var toPlayable: PlayableContent {
        return PlayableContent(
            title: attributes.name,
            subtitle: "",
            thumbnail: attributes.artwork.urlWithSize(width: 100, height: 100),
            artwork: attributes.artwork.urlWithSize(width: 600, height: 600),
            content: MediaContent(
                service: .apple,
                id: id.description,
                type: .libraryPlaylist,
                location: nil
            ),
            metadata: .init()
        )
    }
}

extension AppleLibraryItem {
    public var toPlayable: PlayableContent? {
        guard let contentType = ContentType(type), let name = attributes.name else { return nil }
        var trackDuration: Duration? = nil
        if let duration = attributes.durationInMillis {
            trackDuration = Duration.milliseconds(duration)
        }

        let resolvedType: ContentType = (attributes.isLive == true && contentType == .radio) ? .liveRadio : contentType

        return PlayableContent(
            title: name,
            subtitle:  [attributes.artistName, attributes.releaseDateFormatted].compactMap{ $0 }.joined(separator: " • "),
            thumbnail: attributes.artwork?.urlWithSize(width: 100, height: 100),
            artwork: attributes.artwork?.urlWithSize(width: 600, height: 600),
            content: MediaContent(
                service: .apple,
                id: id.description,
                type: resolvedType,
                location: nil
            ),
            // Library items only carry a preview via the included catalog
            // relationship (see AppleLibraryItem.previewURL).
            previewURL: previewURL,
            metadata: .init(
                duration: trackDuration,
                popularity: 50,
                artist: attributes.artistName,
                album: attributes.albumName,
                isExplicit: attributes.contentRating == "explicit"
            )
        )
    }
}

extension AppleLibraryAlbum {
    public var toPlayable: PlayableContent? {
        return PlayableContent(
            title: attributes.name,
            subtitle: [
                attributes.artistName,
                attributes.trackCount.songCountLabel
            ].compactMap { $0 }.joined(separator: " • "),
            thumbnail: attributes.artwork?.urlWithSize(width: 100, height: 100),
            artwork: attributes.artwork?.urlWithSize(width: 600, height: 600),
            content: MediaContent(
                service: .apple,
                id: id.description,
                type: .libraryAlbum,
                location: nil
            ),
            metadata: .init(
                popularity: 50,
                artist: attributes.artistName
            )
        )
    }
}

extension Album {
    /// An album from the user's library, as `MusicLibraryRequest` hands it
    /// over: the same row `AppleLibraryItem.toPlayable` makes from the web
    /// API — artist and year — so a list can page from either. Library
    /// artwork can come as a `musickit://` URL wrapping the real one, which
    /// is unwrapped the way `toPlayableLibraryTrack` does.
    public var toPlayableLibraryAlbum: PlayableContent {
        PlayableContent(
            title: title,
            subtitle: [
                artistName,
                releaseDate?.formatted(.dateTime.year())
            ].compactMap { $0 }.joined(separator: " • "),
            thumbnail: Self.unwrappingMusicKitArtwork(artwork?.url(width: 100, height: 100)),
            artwork: Self.unwrappingMusicKitArtwork(artwork?.url(width: 600, height: 600)),
            content: MediaContent(service: .apple, id: id.description, type: .libraryAlbum, location: nil),
            metadata: PlayableContentMetadata(
                popularity: 50,
                artist: artistName,
                album: title,
                albumYear: releaseDate
            )
        )
    }

    private static func unwrappingMusicKitArtwork(_ url: URL?) -> URL? {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              components.scheme?.lowercased() == "musickit",
              let regex = try? NSRegularExpression(pattern: "https%3A%2F%2F[^&]+") else {
            return url
        }
        let nsString = url.absoluteString as NSString
        guard let match = regex.firstMatch(in: url.absoluteString, range: NSRange(location: 0, length: nsString.length)) else {
            return url
        }
        return URL(string: nsString.substring(with: match.range).removingPercentEncoding ?? "")
    }

   public var toPlayable: PlayableContent {
        PlayableContent(
            title: title,
            subtitle: [
                artistName,
                releaseDate?.formatted(.dateTime.year()),
                (trackCount as Int?).flatMap(\.songCountLabel)
            ].compactMap { $0 }.joined(separator: " • "),
            thumbnail: artwork?.url(width: 100, height: 100),
            artwork: artwork?.url(width: 600, height: 600),
            content: MediaContent(service: .apple, id: id.description, type: .album, location: url),
            metadata: PlayableContentMetadata(
                artist: artistName,
                album: title,
                albumYear: releaseDate,
                audioCodec: audioVariants?.map(\.description).reduce("", +),
                isPlayable: playParameters != nil,
                isExplicit:  contentRating == .explicit,
                isSingle: isSingle ?? false
            )
        )
    }
}


extension Artist {
   public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: "",
            thumbnail: artwork?.url(width: 100, height: 100),
            artwork: artwork?.url(width: 600, height: 600),
            content: MediaContent(service: .apple, id: id.description, type: .artist, location: url)
        )
    }
}

extension AppleLibraryArtist {
    public var toPlayable: PlayableContent? {
        return PlayableContent(
            title: attributes.name,
            subtitle: "",
            thumbnail: attributes.artwork?.urlWithSize(width: 100, height: 100),
            artwork: nil,
            content: MediaContent(
                service: .apple,
                id: id.description,
                type: .libraryArtist,
                location: nil
            ),
            metadata: .init(
                popularity: 50
            )
        )
    }
}

// MARK: - Spotify Updated Lookup
extension SpotifySongDetails {
    public var toAlbumPlayable: PlayableContent {
        PlayableContent(
            title: album,
            subtitle: artist,
            thumbnail: URL(string: albumArtURI),
            artwork: URL(string: albumArtURI),
            content: .init(service: .spotify, id: albumIdOnly, type: .album, location: nil),
            metadata: PlayableContentMetadata(
                artist: artist,
                album: album,
                isExplicit: isExplicit
            )
        )
    }
}

extension SpotifySongDetails {
    public var toPlayable: PlayableContent? {
        PlayableContent(
            title: title,
            subtitle: artist,
            thumbnail: URL(string: albumArtURI),
            artwork: URL(string: albumArtURI),
            content: .init(service: .spotify, id: trackIDOnly, type: .track, location: nil),
            metadata: PlayableContentMetadata(
                duration: Duration.milliseconds(
                    duration
                ),
                artist: artist,
                album: album,
                isExplicit: isExplicit
            )
        )
    }
}

extension SpotifyTrack {
    public var toPlayable: PlayableContent? {
        PlayableContent(
            title: title,
            subtitle: artist,
            thumbnail: URL(string: albumArtURI),
            artwork: URL(string: albumArtURI),
            content: .init(service: .spotify, id: trackIdOnly, type: .track, location: nil),
            metadata: PlayableContentMetadata(
                duration: Duration.milliseconds(
                    duration
                ),
                artist: artist,
                album: album,
                isExplicit: isExplicit
            )
        )
    }
}


extension SpotifyArtist {
    public var toPlayable: PlayableContent? {
        guard itemType == "album" else { return nil }
        return PlayableContent(
            title: name,
            subtitle: artist ?? "",
            thumbnail: URL(string: albumArtURI),
            artwork: URL(string: albumArtURI),
            content: .init(service: .spotify, id: albumIdOnly, type: .album, location: nil)
        )
    }
}

extension SpotifySongDetails {
    public var toArtistPlayable: PlayableContent {
        PlayableContent(
            title: artist,
            subtitle: "",
            thumbnail: URL(string: albumArtURI),
            artwork: URL(string: albumArtURI),
            content: .init(service: .spotify, id: artistIdOnly, type: .artist, location: nil)
        )
    }
}

extension SpotifyAlbum {
    public var toPlayable: PlayableContent? {
        PlayableContent(
            title: title,
            subtitle: artist,
            thumbnail: URL(string: albumArtURI),
            artwork: URL(string: albumArtURI),
            content: .init(service: .spotify, id: albumIdOnly, type: .album, location: nil),
            metadata: PlayableContentMetadata(
                artist: artist,
                album: title,
            )
        )
    }
}

extension SpotifyAlbumTrack {
    public var toPlayable: PlayableContent? {
        PlayableContent(
            title: title,
            subtitle: artist,
            thumbnail: URL(string: albumArtURI),
            artwork: URL(string: albumArtURI),
            content: .init(service: .spotify, id: trackIdOnly, type: .track, location: nil),
            metadata: PlayableContentMetadata(
                duration: Duration.milliseconds(
                    duration
                ),
                artist: artist,
                album: album,
                isExplicit: isExplicit
            )
        )
    }
}


extension SpotifyPlaylist {
    public var toPlayable: PlayableContent? {
        PlayableContent(
            title: title,
            subtitle: description ?? "",
            thumbnail: URL(string: albumArtURI),
            artwork: URL(string: albumArtURI),
            content: .init(service: .spotify, id: IdOnly, type: .playlist, location: nil)
        )
    }
}

// MARK: - Spotify Music Mapping
extension SpotifyTrackItem {
    public var toPlayable: PlayableContent? {
        guard let id else { return nil }

        return PlayableContent(
            title: name,
            subtitle: allArtists,
            thumbnail: album.images?.thumbnail,
            artwork: album.images?.biggestImageURL,
            content: MediaContent(
                service: .spotify,
                id: id,
                type: .track,
                location: URL(string: externalUrls.spotify ?? "")
            ),
            previewURL: URL(string: previewUrl ?? ""),
            metadata: PlayableContentMetadata(
                duration: Duration.milliseconds(
                    durationMs
                ),
                popularity: popularity,
                artist: artists.first?.name,
                album: album.name,
                isrc: externalIds.isrc,
                isExplicit: explicit
            )
        )
    }
}

extension SpotifyAlbumItem {
    public var toPlayable: PlayableContent? {
        guard let id else { return nil }
        return PlayableContent(
            title: name,
            subtitle: [artists?.first?.name, releaseDateFormatted, totalTracks.flatMap(\.songCountLabel)].compactMap{ $0 }.joined(separator: " • "),
            thumbnail: images?.thumbnail,
            artwork: images?.biggestImageURL,
            content: MediaContent(service: .spotify, id: id, type: .album, location: URL(string: externalUrls?.spotify ?? "")),
            metadata: .init(
                artist: artists?.first?.name,
                artistID: artists?.first?.id,
                album: name,
                albumYear: releaseYear
            )
        )
    }
}

extension SpotifyArtistAlbums.AlbumItem {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: releaseDateFormatted ?? "",
            thumbnail: images.thumbnail,
            artwork: images.biggestImageURL,
            content: MediaContent(service: .spotify, id: id, type: .album, location: URL(string: externalUrls.spotify ?? "")),
            metadata: PlayableContentMetadata(
                artist: artists?.first?.name,
                album: name,
            )
        )
    }
}

extension SpotifyAlbumDetails {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: releaseDateFormatted ?? "",
            thumbnail: images.thumbnail,
            artwork: images.biggestImageURL,
            content: MediaContent(service: .spotify, id: id, type: .album, location: URL(string: externalUrls.spotify ?? "")),
            metadata: PlayableContentMetadata(
                duration: Duration.milliseconds(
                    durationMs ?? 0
                ),
                artist: artists?.first?.name,
                album: name,
                isExplicit: explicit
            )
        )
    }
}

extension SpotifyAlbumTrackItems {
    public func toPlayable(album: PlayableContent?, thumbnail: URL?, artwork: URL?, fingerprint: String? = nil) -> PlayableContent? {
        guard let id else { return nil }
        return PlayableContent(
            title: name,
            subtitle: allArtists,
            thumbnail: thumbnail,
            artwork: artwork,
            content: MediaContent(service: .spotify, id: id, type: .track, location: URL(string: externalUrls?.spotify ?? "")),
            previewURL: URL(string: previewUrl ?? ""),
            metadata: PlayableContentMetadata(
                duration: Duration.milliseconds(
                    durationMs
                ),
                artist: artists.first?.name,
                album: self.album?.name,
                isExplicit: explicit,
                fingerprint: fingerprint
            )
        )
    }
}

extension SpotifyPlaylistItems {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: owner.displayName,
            thumbnail: images?.thumbnail,
            artwork: images?.biggestImageURL,
            content: MediaContent(service: .spotify, id: id, type: .playlist, location: URL(string: externalUrls.spotify ?? ""))
        )
    }
}

extension SpotifyArtistsItems {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: "",
            thumbnail: images.thumbnail,
            artwork: images.biggestImageURL,
            content: MediaContent(service: .spotify, id: id, type: .artist, location: URL(string:  externalUrls.spotify ?? "")),
            metadata: .init(popularity: popularity)
        )
    }
}

extension SpotifyUserPlaylists {
    public var toPlayable: PlayableContent? {
        PlayableContent(
            title: name,
            subtitle: "",
            thumbnail: images?.thumbnail,
            artwork: images?.biggestImageURL,
            content: MediaContent(service: .spotify, id: id, type: .playlist, location: URL(string: externalUrls.spotify ?? "")),
            metadata: nil
        )
    }
}

// MARK: Plex
extension PlexTrack {
    public var toPlayable: PlayableContent {
        var trackDuration: Duration? = nil
        if let duration {
            trackDuration = Duration.milliseconds(duration)
        }
        return PlayableContent(
            title: title,
            // Codec and bitrate tell duplicate editions apart: a Plex library
            // can hold the same track from several rips (FLAC vs 320 kbps),
            // which otherwise render as identical rows.
            subtitle: [artist, audioCodec?.uppercased() ?? "", bitrate.map { "\($0) kbps" } ?? ""].filter { !$0.isEmpty }.joined(separator: " • "),
            // TODO: Add Thumbnail
            thumbnail: imageURL,
            artwork: imageURL,
            content: .init(
                service: .plex,
                id: id,
                type: .track,
                location: nil
            ),
            metadata: .init(
                duration: trackDuration,
                popularity: nil,
                artist: artist,
                artistID: grandparentRatingKey,
                album: album,
                albumID: parentRatingKey,
                albumYear: nil,
                audioCodec: audioCodec,
                librarySectionID: librarySectionID.map(String.init),
                userRating: userRating
            )
        )
    }
}

extension PlexAlbum {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: title,
            // Track count tells editions of the same album apart (standard vs
            // deluxe rips share title, artist, and year). Plex puts no media
            // info on album containers, so count + artwork are the available
            // distinguishers.
            subtitle: [
                artist,
                year,
                leafCount.flatMap(\.songCountLabel) ?? ""
            ].filter { !$0.isEmpty }.joined(separator: " • "),
            thumbnail: imageURL,
            artwork: imageURL,
            content: .init(
                service: .plex,
                id: id,
                type: .album,
                location: nil
            ),
            metadata: .init(
                popularity: nil,
                artist: artist,
                artistID: parentRatingKey,
                album: title,
                // The album's own ratingKey: pairs with the track mapping's
                // parentRatingKey so a track and its album share an artwork
                // cache entry, while different editions of the album don't.
                albumID: ratingKey,
                albumYear: nil,
                librarySectionID: librarySectionID.map(String.init),
                userRating: userRating
            )
        )
    }
}

extension PlexAlbumItem {
    public var toPlayable: PlayableContent? {
        guard let id = sonosID, let title else { return nil }
        if type == "artist" {
            return PlayableContent(
                title: title,
                subtitle: "",
                thumbnail: thumbImageURL?.plexResized(to: PlexImageSize.thumbnail),
                artwork: thumbImageURL?.plexResized(to: PlexImageSize.artwork),
                content: .init(service: .plex, id: id, type: .artist, location: nil),
                metadata: .init(popularity: nil)
            )
        }
        return PlayableContent(
            title: title,
            subtitle: [parentTitle, year?.description].compactMap{ $0 }.joined(separator: " • "),
            thumbnail: thumbImageURL?.plexResized(to: PlexImageSize.thumbnail),
            artwork: thumbImageURL?.plexResized(to: PlexImageSize.artwork),
            content: .init(
                service: .plex,
                id: id,
                type: .album,
                location: nil
            ),
            metadata: .init(
                popularity: nil,
                artist: parentTitle,
                artistID: parentRatingKey,
                album: title,
                albumYear: nil
            )
        )
    }
}

extension PlexLibraryItem {
    public var toPlayable: PlayableContent? {
        guard let parentTitle else { return nil }
        return PlayableContent(
            title: parentTitle,
            subtitle: [grandparentTitle, parentYear?.description].compactMap{ $0 }.joined(separator: " • "),
            thumbnail: thumbImageURL?.plexResized(to: PlexImageSize.thumbnail),
            artwork: thumbImageURL?.plexResized(to: PlexImageSize.artwork),
            content: .init(
                service: .plex,
                id: sonosID!,
                type: .album,
                location: nil
            ),
            metadata: .init(
                popularity: nil,
                artist: grandparentTitle,
                artistID: grandparentRatingKey?.description,
                album: parentTitle,
                albumID: key,
                albumYear: nil,
                audioCodec: nil
            )
        )
    }
}

extension PlexMetadata {
    public var toPlayable: PlayableContent {
        var artist: String?
        var artistID: String?
        var album: String?
        var albumID: String?
        var audioCodec: String?

        switch type {
        case "track":
            artist = grandparentTitle
            artistID = grandparentRatingKey
            album = parentTitle
            albumID = parentRatingKey
            audioCodec = media?.first?.audioCodec
        case "album":
            artist = parentTitle
            artistID = parentRatingKey
            // The album's own key: without it, artist-detail/browse albums
            // fell back to the shared title+artist artwork cache key, so two
            // editions of the same album showed one edition's art — the exact
            // bug the per-edition imageKey fixed in search.
            albumID = ratingKey
        case "playlist":
            break
        case "artist":
            break
        default:
            break
        }
       
        return PlayableContent(
            title: title,
            subtitle: [artist, parentYear?.description, audioCodec?.uppercased()].compactMap{ $0 }.joined(separator: " • "),
            thumbnail: thumbImageURL?.plexResized(to: PlexImageSize.thumbnail),
            artwork: thumbImageURL?.plexResized(to: PlexImageSize.artwork),
            content: .init(
                service: .plex,
                id: sonosID!,
                type: ContentType(type)!,
                location: nil
            ),
            // Plex has no short preview clip — this is the full track streamed
            // from the user's server (see AudioPlaybackService streaming path).
            previewURL: streamURL,
            metadata: .init(
                duration: Duration.milliseconds(duration ?? 0),
                popularity: ratingCount,
                artist: artist,
                artistID: artistID,
                album: album,
                albumID: albumID,
                audioCodec: audioCodec,
                userRating: userRating,
                playlistItemID: playlistItemID.map(String.init)
            )
        )
    }
}


extension PlexUserPlaylist {
    public var toPlayable: PlayableContent {
        return PlayableContent(
            title: title,
            subtitle: "",
            thumbnail: thumbImageURL?.plexResized(to: PlexImageSize.thumbnail),
            artwork: thumbImageURL?.plexResized(to: PlexImageSize.artwork),
            content: .init(
                service: .plex,
                id: sonosID!,
                type: .playlist,
                location: nil
            )
        )
    }
}

extension PlexAlbumHub {
    public var toPlayable: PlayableContent {
        return PlayableContent(
            title: title,
            subtitle: "\(size) albums",
            thumbnail: nil,
            artwork: nil,
            content: .init(
                service: .plex,
                id: hubIdentifier ?? title,
                type: .album,
                location: nil
            ),
            metadata: .init(
                popularity: size
            )
        )
    }
}

extension PlexArtist {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: "",
            thumbnail: imageURL,
            artwork: imageURL,
            content: .init(
                service: .plex,
                id: id,
                type: .artist,
                location: nil
            ),
            metadata: .init(
                librarySectionID: librarySectionID.map(String.init)
            )
        )
    }
}

extension PlexPlaylist {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: title,
            subtitle: "",
            thumbnail: imageURL,
            artwork: imageURL,
            content: .init(
                service: .plex,
                id: id,
                type: .playlist,
                location: nil
            )
        )
    }
}

// MARK: Tidal
extension TidalTrackResource {
    public var toPlayable: PlayableContent {
        let artist = artists.first { $0.main ?? false }
        return PlayableContent(
            title: title,
            subtitle: artists.first?.name ?? "",
            thumbnail: album?.imageCover?.thumbnail,
            artwork: album?.imageCover?.biggestImageURL,
            content: .init(
                service: .tidal,
                id: id,
                type: .track,
                location: URL(string: tidalUrl)
            ),
            metadata: .init(
                duration: Duration.seconds(
                    duration
                ),
                popularity: Int(popularity),
                artist: artist?.name,
                artistID: artist?.id,
                album: album?.title,
                albumID: album?.id,
                isrc: isrc,
                audioCodec: mediaMetadata?.first,
                isExplicit: isExplicit
            )
        )
    }
}

// MARK: Tidal
extension TidalAlbumResource {
    public var toPlayable: PlayableContent {
        let artist = artists.first { $0.main ?? false }
        return PlayableContent(
            title: title,
            subtitle: [artist?.name, releaseDateFormatted, numberOfTracks.flatMap(\.songCountLabel), dolbyAtmos, lossless].compactMap{ $0 }.joined(separator: " • "),
            thumbnail: imageCover?.thumbnail,
            artwork: imageCover?.biggestImageURL,
            content: .init(
                service: .tidal,
                id: id,
                type: .album,
                location: URL(string: tidalUrl)
            ),
            metadata: .init(
                duration: Duration.seconds(
                    duration
                ),
                popularity: Int(popularity),
                artist: artist?.name,
                artistID: artist?.id,
                album: title,
                albumID: id,
                isExplicit: isExplicit
            )
        )
    }
}

// MARK: Tidal
extension TidalPlaylistResource {
    public var toPlayable: PlayableContent {
        return PlayableContent(
            title: name,
            subtitle: "",
            thumbnail: imageUrls.thumbnail,
            artwork: imageUrls.biggestImageURL,
            content: MediaContent(
                service: .tidal,
                id: id.description,
                type: .playlist,
                location: nil
            )
        )
    }
}

extension TidalArtistResource {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: "",
            thumbnail: picture.thumbnail,
            artwork: picture.biggestImageURL,
            content: .init(
                service: .tidal,
                id: id,
                type: .artist,
                location: URL(string: tidalUrl ?? "")
            ),
            metadata: .init(popularity: Int(popularity))
        )
    }
}

extension TuneInStation {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: title,
            subtitle: [stationInfo?.song, stationInfo?.artist].compactMap{
                $0
            }.filter({ !$0.isEmpty }).joined(separator: " • "),
            thumbnail: imageURL,
            artwork: imageURL,
            content: .init(
                service: .tuneIn,
                id: id,
                type: .radio,
                location: url
            ),
            metadata: .init(
                artist: stationInfo?.artist,
                album: stationInfo?.album
            )
        )
    }
}

// MARK: Subsonic
extension SubsonicSong {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: title ?? "",
            subtitle: [artist ?? "", suffix?.uppercased() ?? ""].filter { !$0.isEmpty }.joined(separator: " • "),
            thumbnail: SubsonicAPI.coverArtURL(for: coverArt, size: 300),
            artwork: SubsonicAPI.coverArtURL(for: coverArt, size: SubsonicAPI.artworkSize),
            content: .init(
                service: .subsonic,
                id: id,
                type: .track,
                location: nil
            ),
            // Like Plex, there is no short clip — the full-track stream is the
            // preview, played through the streaming AVPlayer path. Same URL
            // shape as playback (suffix included) so the two share caching.
            previewURL: SubsonicAPI.streamURL(for: id, fileExtension: suffix),
            metadata: .init(
                duration: duration.map { Duration.seconds($0) },
                popularity: nil,
                artist: artist,
                artistID: artistId,
                album: album,
                albumID: albumId,
                audioCodec: suffix,
                // 0 rather than nil: "not starred" is an answer, and nil
                // sends FavoriteMenuButton to the network for every row.
                userRating: starred != nil ? 1 : 0
            )
        )
    }
}

extension SubsonicAlbum {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: displayName,
            subtitle: [
                artist ?? "",
                year.map(String.init) ?? "",
                songCount.flatMap(\.songCountLabel) ?? ""
            ].filter { !$0.isEmpty }.joined(separator: " • "),
            thumbnail: SubsonicAPI.coverArtURL(for: coverArt, size: 300),
            artwork: SubsonicAPI.coverArtURL(for: coverArt, size: SubsonicAPI.artworkSize),
            content: .init(
                service: .subsonic,
                id: id,
                type: .album,
                location: nil
            ),
            metadata: .init(
                popularity: nil,
                artist: artist,
                artistID: artistId,
                album: displayName,
                albumID: id,
                // Release year as a date so the artist screen's year sorting
                // (and Discography's oldest-first playback) can order albums.
                albumYear: year.flatMap { Calendar.current.date(from: DateComponents(year: $0)) }
            )
        )
    }
}

extension SubsonicArtist {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name ?? "",
            subtitle: "",
            thumbnail: SubsonicAPI.coverArtURL(for: coverArt, size: 300),
            artwork: SubsonicAPI.coverArtURL(for: coverArt, size: SubsonicAPI.artworkSize),
            content: .init(
                service: .subsonic,
                id: id,
                type: .artist,
                location: nil
            ),
            metadata: .init(popularity: nil)
        )
    }
}

extension SubsonicPlaylist {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name ?? "",
            subtitle: [
                owner ?? "",
                songCount.flatMap(\.songCountLabel) ?? ""
            ].filter { !$0.isEmpty }.joined(separator: " • "),
            thumbnail: SubsonicAPI.coverArtURL(for: coverArt, size: 300),
            artwork: SubsonicAPI.coverArtURL(for: coverArt, size: SubsonicAPI.artworkSize),
            content: .init(
                service: .subsonic,
                id: id,
                type: .playlist,
                location: nil
            )
        )
    }
}
