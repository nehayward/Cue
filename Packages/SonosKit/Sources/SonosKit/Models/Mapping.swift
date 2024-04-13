import Foundation
import MusicKit
import MusicSearchKit

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
        PlayableContent(
            title: title,
            subtitle: artistName,
            artwork: artwork?.url(width: 100, height: 100),
            content: MediaContent(service: .apple, id: id.description, type: .track, location: url)
        )
    }
}

extension Playlist {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: curatorName ?? "",
            artwork: artwork?.url(
                width: 100,
                height: 100
            ),
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
            content: MediaContent(service: .spotify, id: id, type: .track, location: nil))
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

extension SpotifyAlbumTrackItems {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: allArtists,
            artwork: nil,
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
            artwork: URL(string: images.first?.url ?? ""),
            content: MediaContent(service: .spotify, id: id, type: .playlist, location: nil)
        )
    }
}

extension SpotifyArtistsItems {
    public var toPlayable: PlayableContent {
        PlayableContent(
            title: name,
            subtitle: "",
            artwork: URL(string: images.last?.url ?? ""),
            content: MediaContent(service: .spotify, id: id, type: .artist, location: nil)
        )
    }
}
