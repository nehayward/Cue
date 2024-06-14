import Foundation
import MusicKit
import MusicSearchKit

extension Track {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: song,
            subtitle: [artist, album].filter({ !$0.isEmpty }).joined(separator: " • "),
            artwork: artworkURL,
            content: MediaContent(service: musicService, id: trackID.description, type: .track, location: metadata?.openInURL),
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
            artwork: artwork?.url(width: 100, height: 100),
            content: MediaContent(service: .apple, id: id.description, type: .track, location: url),
            metadata: PlayableContentMetadata(artist: artistName, album: albumTitle, isrc: isrc)
        )
    }
}

extension MusicKit.Track {
    public var toPlayable: PlayableContent {
        var durationSeconds: Duration?
        if let duration {
            durationSeconds = Duration.seconds(duration)
        }

        var artworkURL = artwork?.url(width: 200, height: 200)

        if let artworkURLFound = artworkURL,
            let components = URLComponents(url: artworkURLFound, resolvingAgainstBaseURL: true),
            components.scheme?.lowercased() == "musickit" {
            let pattern = "https%3A%2F%2F[^&]+"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsString = artworkURLFound.absoluteString as NSString
                let results = regex.matches(in: artworkURLFound.absoluteString, range: NSRange(location: 0, length: nsString.length))

                if let match = results.first {
                    let encodedUrl = nsString.substring(with: match.range)
                    artworkURL = URL(string: encodedUrl.removingPercentEncoding ?? "")
                }
            }
        }

        return PlayableContent(
            title: title,
            subtitle: artistName,
            artwork: artworkURL,
            content: MediaContent(service: .apple, id: id.description, type: .track, location: url),
            metadata: PlayableContentMetadata(duration: durationSeconds, artist: artistName, album: albumTitle, isrc: isrc)
        )
    }

    public var toPlayableLibraryTrack: PlayableContent {
        var durationSeconds: Duration?
        if let duration {
            durationSeconds = Duration.seconds(duration)
        }

        var artworkURL = artwork?.url(width: 200, height: 200)

        if let artworkURLFound = artworkURL,
            let components = URLComponents(url: artworkURLFound, resolvingAgainstBaseURL: true),
            components.scheme?.lowercased() == "musickit" {
            let pattern = "https%3A%2F%2F[^&]+"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsString = artworkURLFound.absoluteString as NSString
                let results = regex.matches(in: artworkURLFound.absoluteString, range: NSRange(location: 0, length: nsString.length))

                if let match = results.first {
                    let encodedUrl = nsString.substring(with: match.range)
                    artworkURL = URL(string: encodedUrl.removingPercentEncoding ?? "")
                }
            }
        }
        return PlayableContent(
            title: title,
            subtitle: artistName,
            artwork: artworkURL,
            content: MediaContent(service: .apple, id: id.description, type: .libraryTrack, location: url),
            metadata: PlayableContentMetadata(duration: durationSeconds, artist: artistName, album: albumTitle, isrc: isrc)
        )
    }
}

extension Playlist {
    public func toPlayable(isUserPlaylist: Bool = false) ->  PlayableContent {
        var artworkURL = artwork?.url(width: 200, height: 200)

        if let artworkURLFound = artworkURL,
            let components = URLComponents(url: artworkURLFound, resolvingAgainstBaseURL: true),
            components.scheme?.lowercased() == "musickit" {
            let pattern = "https%3A%2F%2F[^&]+"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsString = artworkURLFound.absoluteString as NSString
                let results = regex.matches(in: artworkURLFound.absoluteString, range: NSRange(location: 0, length: nsString.length))

                if let match = results.first {
                    let encodedUrl = nsString.substring(with: match.range)
                    artworkURL = URL(string: encodedUrl.removingPercentEncoding ?? "")
                }
            }
        }

        return PlayableContent(
            title: name,
            subtitle: curatorName ?? "",
            artwork: artworkURL,
            content: MediaContent(
                service: .apple,
                id: id.description,
                type: isUserPlaylist ? .userPlaylist : .playlist,
                location: nil
            )
        )
    }
}

extension Album {
   public var toPlayable: PlayableContent {
        PlayableContent(
            title: title,
            subtitle: artistName,
            artwork: artwork?.url(width: 100, height: 100),
            content: MediaContent(service: .apple, id: id.description, type: .album, location: nil)
        )
    }
}


extension Artist {
   public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: "",
            artwork: artwork?.url(width: 100, height: 100),
            content: MediaContent(service: .apple, id: id.description, type: .artist, location: nil)
        )
    }
}


// MARK: - Spotify Music Mapping
extension SpotifyTrackItem {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: allArtists,
            artwork: URL(string: album.images.first?.url ?? ""),
            content: MediaContent(
                service: .spotify,
                id: id,
                type: .track,
                location: nil
            ),
            metadata: PlayableContentMetadata(
                duration: Duration.seconds(
                    durationMs
                ),
                popularity: popularity,
                artist: artists.first?.name,
                album: album.name,
                isrc: externalIds.isrc
            )
        )
    }
}

extension SpotifyAlbumItem {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: artists.first?.name ?? "",
            artwork: URL(string: images.first?.url ?? ""),
            content: MediaContent(service: .spotify, id: id, type: .album, location: nil)
        )
    }
}

extension SpotifyArtistAlbums.AlbumItem {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: releaseDate,
            artwork: URL(string: images.first?.url ?? ""),
            content: MediaContent(service: .spotify, id: id, type: .album, location: nil)
        )
    }
}

extension SpotifyAlbumDetails {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: releaseDate,
            artwork: URL(string: images.first?.url ?? ""),
            content: MediaContent(service: .spotify, id: id, type: .album, location: nil)
        )
    }
}

extension SpotifyAlbumTrackItems {
    public func toPlayable(artwork: URL?) -> PlayableContent {
        PlayableContent(
            title: name,
            subtitle: allArtists,
            artwork: artwork,
            content: MediaContent(service: .spotify, id: id, type: .track, location: nil),
            metadata: .init(duration: Duration.milliseconds(durationMs))
        )
    }
}

extension SpotifyPlaylistItems {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: owner.displayName,
            artwork: images.biggestImageURL,
            content: MediaContent(service: .spotify, id: id, type: .playlist, location: nil)
        )
    }
}

extension SpotifyArtistsItems {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: "",
            artwork: images.biggestImageURL,
            content: MediaContent(service: .spotify, id: id, type: .artist, location: nil),
            metadata: .init(popularity: popularity)
        )
    }
}

// MARK: Favorites
extension Favorite {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: description,
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
        PlayableContent(
            title: title,
            subtitle: artist,
            artwork: imageURL,
            content: .init(
                service: .plex,
                id: id,
                type: .track,
                location: nil
            )
        )
    }
}

extension PlexAlbum {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: title,
            subtitle: "\(artist) • \(year)",
            artwork: imageURL,
            content: .init(
                service: .plex,
                id: id,
                type: .album,
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
            artwork: URL(string: album.imageCover.first(where: { $0.width == $0.height })?.url ?? ""),
            content: .init(
                service: .tidal,
                id: id,
                type: .track,
                location: URL(string: tidalUrl)
            ),
            metadata: .init(duration: Duration.seconds(duration), artist: artist?.name, artistID: artist?.id, album: album.title, albumID: album.id, isrc: isrc)
        )
    }
}

// MARK: Tidal
extension TidalAlbumResource {
    public var toPlayable: PlayableContent {
        let artist = artists.first { $0.main ?? false }
        return PlayableContent(
            title: title,
            subtitle: artists.first?.name ?? "",
            artwork: URL(string: imageCover?.first(where: { $0.width == $0.height })?.url ?? ""),
            content: .init(
                service: .tidal,
                id: id,
                type: .album,
                location: URL(string: tidalUrl)
            ),
            metadata: .init(duration: Duration.seconds(duration), artist: artist?.name, artistID: artist?.id, album: title, albumID: id)
        )
    }
}

extension TidalArtistResource {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: "",
            artwork: URL(string: picture.first(where: { $0.width == $0.height })?.url ?? ""),
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
