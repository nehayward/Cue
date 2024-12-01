import Foundation
import MusicKit
import MusicSearchKit

extension Track {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: song,
            subtitle: [artist, album].filter({ !$0.isEmpty }).joined(separator: " • "),
            thumbnail: artworkURL,
            artwork: artworkURL,
            content: MediaContent(service: musicService, id: trackID.description, type: trackID.contains("i.") ? .libraryTrack : .track, location: metadata?.openInURL),
            metadata: PlayableContentMetadata(duration: Duration.seconds(duration), artist: artist, album: album)
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
            metadata: PlayableContentMetadata(
                artist: artistName,
                album: albumTitle,
                isrc: isrc,
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

        return PlayableContent(
            title: title,
            subtitle: artistName,
            thumbnail: thumbnailURL,
            artwork: artworkURL,
            content: MediaContent(service: .apple, id: id.description, type: .track, location: url),
            metadata: PlayableContentMetadata(
                duration: durationSeconds,
                artist: artistName,
                album: albumTitle,
                isrc: isrc,
                isPlayable: playParameters != nil,
                isExplicit: contentRating == .explicit,
                parent: albums?.first?.toPlayable
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
                isrc: isrc
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
            )
        )
    }
}

extension AppleLibraryItem {
    public var toPlayable: PlayableContent? {
        guard let contentType = ContentType(type) else { return nil }
        var trackDuration: Duration? = nil
        if let duration = attributes.durationInMillis {
            trackDuration = Duration.milliseconds(duration)
        }
    
        return PlayableContent(
            title: attributes.name,
            subtitle:  [attributes.artistName, attributes.releaseDateFormatted].compactMap{ $0 }.joined(separator: " • "),
            thumbnail: attributes.artwork?.urlWithSize(width: 100, height: 100),
            artwork: attributes.artwork?.urlWithSize(width: 600, height: 600),
            content: MediaContent(
                service: .apple,
                id: id.description,
                type: contentType,
                location: nil
            ),
            metadata: .init(
                duration: trackDuration,
                popularity: 50,
                artist: attributes.artistName,
                isExplicit: attributes.contentRating == "explicit"
            )
        )
    }
}

extension AppleLibraryAlbum {
    public var toPlayable: PlayableContent? {
        return PlayableContent(
            title: attributes.name,
            subtitle: "\(attributes.artistName ?? "")",
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
   public var toPlayable: PlayableContent {
        PlayableContent(
            title: title,
            subtitle: artistName + " • \(releaseDate?.formatted(.dateTime.year()) ?? "")",
            thumbnail: artwork?.url(width: 100, height: 100),
            artwork: artwork?.url(width: 600, height: 600),
            content: MediaContent(service: .apple, id: id.description, type: .album, location: url),
            metadata: PlayableContentMetadata(
                artist: artistName,
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
            thumbnail: nil,
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

// MARK: - Spotify Music Mapping
extension SpotifyTrackItem {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: allArtists,
            thumbnail: album.images.thumbnail,
            artwork: album.images.biggestImageURL,
            content: MediaContent(
                service: .spotify,
                id: id,
                type: .track,
                location: URL(string: externalUrls.spotify)
            ),
            metadata: PlayableContentMetadata(
                duration: Duration.milliseconds(
                    durationMs
                ),
                popularity: popularity,
                artist: artists.first?.name,
                album: album.name,
                isrc: externalIds.isrc,
                isExplicit: explicit,
                parent: album.toPlayable
            )
        )
    }
}

extension SpotifyAlbumItem {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: [artists.first?.name, releaseDateFormatted].compactMap{ $0 }.joined(separator: " • "),
            thumbnail: images.thumbnail,
            artwork: images.biggestImageURL,
            content: MediaContent(service: .spotify, id: id, type: .album, location: URL(string: externalUrls.spotify)),
            metadata: .init(
                artistID: artists.first?.id,
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
            content: MediaContent(service: .spotify, id: id, type: .album, location: URL(string: externalUrls.spotify))
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
            content: MediaContent(service: .spotify, id: id, type: .album, location: URL(string: externalUrls.spotify))
        )
    }
}

extension SpotifyAlbumTrackItems {
    public func toPlayable(album: PlayableContent?, thumbnail: URL?, artwork: URL?) -> PlayableContent {
        PlayableContent(
            title: name,
            subtitle: allArtists,
            thumbnail: thumbnail,
            artwork: artwork,
            content: MediaContent(service: .spotify, id: id, type: .track, location: URL(string: externalUrls.spotify)),
            metadata: PlayableContentMetadata(
                duration: Duration.milliseconds(
                    durationMs
                ),
                artist: artists.first?.name,
                isExplicit: explicit,
                parent: album
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
            content: MediaContent(service: .spotify, id: id, type: .playlist, location: URL(string: externalUrls.spotify))
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
            content: MediaContent(service: .spotify, id: id, type: .artist, location: URL(string: externalUrls.spotify)),
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
            content: MediaContent(service: .spotify, id: id, type: .playlist, location: URL(string: externalUrls.spotify)),
            metadata: nil
        )
    }
}

// MARK: Favorites
extension Favorite {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: description,
            thumbnail: SonosService.shared.favoriteImageURL(favorite: self),
            artwork: SonosService.shared.favoriteImageURL(favorite: self),
            content: .init(
                service: .unknown,
                id: id,
                type: .favorite,
                location: nil
            )
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
            subtitle: [artist, audioCodec?.uppercased()].compactMap{ $0 }.joined(separator: " • "),
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
                audioCodec: audioCodec
            )
        )
    }
}

extension PlexAlbum {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: title,
            subtitle: "\(artist) • \(year)",
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
                albumYear: nil
            )
        )
    }
}

extension PlexLibraryItem {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: parentTitle,
            subtitle: [grandparentTitle, parentYear?.description].compactMap{ $0 }.joined(separator: " • "),
            thumbnail: thumbImageURL,
            artwork: thumbImageURL,
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
            thumbnail: thumbImageURL,
            artwork: thumbImageURL,
            content: .init(
                service: .plex,
                id: sonosID!,
                type: ContentType(type)!,
                location: nil
            ),
            metadata: .init(
                duration: Duration.milliseconds(duration ?? 0),
                popularity: ratingCount,
                artist: artist,
                artistID: artistID,
                album: album,
                albumID: albumID,
                audioCodec: audioCodec
            )
        )
    }
}


extension PlexUserPlaylist {
    public var toPlayable: PlayableContent {
        return PlayableContent(
            title: title,
            subtitle: "",
            thumbnail: thumbImageURL,
            artwork: thumbImageURL,
            content: .init(
                service: .plex,
                id: sonosID!,
                type: .playlist,
                location: nil
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
            thumbnail: URL(string: album.imageCover.first(where: { $0.width == $0.height })?.url ?? ""),
            artwork: URL(string: album.imageCover.last(where: { $0.width == $0.height })?.url ?? ""),
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
                artist: artist?.name,
                artistID: artist?.id,
                album: album.title,
                albumID: album.id,
                isrc: isrc,
                audioCodec: mediaMetadata.tags?.last?.uppercased(),
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
            subtitle: [artist?.name, releaseDateFormatted].compactMap{ $0 }.joined(separator: " • "),
            thumbnail: imageCover?.thumbnail,
            artwork: imageCover?.thumbnail,
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
                artist: artist?.name,
                artistID: artist?.id,
                album: title,
                albumID: id,
                isExplicit: isExplicit
            )
        )
    }
}

extension TidalArtistResource {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: "",
            thumbnail: URL(string: picture.first(where: { $0.width == $0.height })?.url ?? ""),
            artwork: URL(string: picture.last(where: { $0.width == $0.height })?.url ?? ""),
            content: .init(
                service: .tidal,
                id: id,
                type: .artist,
                location: URL(string: tidalUrl ?? "")
            )
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
