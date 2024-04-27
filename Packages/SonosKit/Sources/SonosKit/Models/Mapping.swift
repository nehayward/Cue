import Foundation
import MusicKit
import MusicSearchKit

extension Track {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: artist,
            artwork: artworkURL,
            content: MediaContent(service: musicService, id: trackID.description, type: .track, location: nil)
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
            content: MediaContent(service: .apple, id: id.description, type: .track, location: url)
        )
    }
}

extension MusicKit.Track {
    public var toPlayable: PlayableContent {
        var durationMs: Duration?
        if let duration {
            durationMs = Duration.seconds(duration)
        }

        return PlayableContent(
            title: title,
            subtitle: artistName,
            artwork: artwork?.url(width: 100, height: 100),
            content: MediaContent(service: .apple, id: id.description, type: .track, location: url),
            duration: durationMs
        )
    }
}

extension Playlist {
    public var toPlayable: PlayableContent {
        var artworkURL = artwork?.url(width: 200, height: 200)

        if let artworkURLFound = artworkURL,
            let components = URLComponents(url: artworkURLFound, resolvingAgainstBaseURL: true),
            components.scheme?.lowercased() == "musickit" {
            let pattern = "https%3A%2F%2F[^&]+"
            do {
                let regex = try NSRegularExpression(pattern: pattern)
                let nsString = artworkURLFound.absoluteString as NSString
                let results = regex.matches(in: artworkURLFound.absoluteString, range: NSRange(location: 0, length: nsString.length))

                if let match = results.first {
                    let encodedUrl = nsString.substring(with: match.range)

                    artworkURL = URL(string: encodedUrl.removingPercentEncoding ?? "")
                }
            } catch {
                
            }
        }

        return PlayableContent(
            title: name,
            subtitle: curatorName ?? "",
            artwork: artworkURL,
            content: MediaContent(
                service: .apple,
                id: id.description,
                type: .playlist,
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
            content: MediaContent(service: .spotify, id: id, type: .track, location: nil)
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
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: allArtists,
            artwork: album?.images.thumbnail,
            content: MediaContent(service: .spotify, id: id, type: .track, location: nil),
            duration: Duration.milliseconds(durationMs)
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
            content: MediaContent(service: .spotify, id: id, type: .artist, location: nil)
        )
    }
}
