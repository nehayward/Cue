import Foundation
#if DEBUG
extension Array where Element == PlayableContent {
    public static var debugSamples: [PlayableContent] {
        [
            // Spotify Track
            PlayableContent(
                title: "Bohemian Rhapsody",
                subtitle: "Queen",
                thumbnail: URL(string: "https://i.scdn.co/image/ab67616d00001e02e319baafd16e84f0408af2a0"),
                artwork: URL(string: "https://i.scdn.co/image/ab67616d0000b273e319baafd16e84f0408af2a0"),
                content: MediaContent(service: .spotify, id: "3z8h0TU7ReDPLIbEnYhWZb", type: .track, location: nil),
                previewURL: URL(string: "https://p.scdn.co/mp3-preview/3z8h0TU7ReDPLIbEnYhWZb"),
                metadata: PlayableContentMetadata(duration: .seconds(354), position: 1)
            ),
            
            // Spotify Album
            PlayableContent(
                title: "A Night at the Opera",
                subtitle: "Queen",
                thumbnail: URL(string: "https://i.scdn.co/image/ab67616d00001e02e319baafd16e84f0408af2a0"),
                artwork: URL(string: "https://i.scdn.co/image/ab67616d0000b273e319baafd16e84f0408af2a0"),
                content: MediaContent(service: .spotify, id: "6X9k3hgEYJX6Ehj8m8KuVB", type: .album, location: nil),
            ),
            
            // Spotify Playlist
            PlayableContent(
                title: "Rock Classics",
                subtitle: "Spotify",
                thumbnail: URL(string: "https://i.scdn.co/image/ab67706f00000002ca5a7517156021292e5663a6"),
                artwork: URL(string: "https://i.scdn.co/image/ab67706c0000da84ca5a7517156021292e5663a6"),
                content: MediaContent(service: .spotify, id: "37i9dQZF1DWXRqgorJj26U", type: .playlist, location: nil),
            ),
            
            // Apple Music Track
            PlayableContent(
                title: "Blinding Lights",
                subtitle: "The Weeknd",
                thumbnail: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/8e/bc/1c/8ebc1c4c.jpg/300x300bb.jpg"),
                artwork: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/8e/bc/1c/8ebc1c4c.jpg/1000x1000bb.jpg"),
                content: MediaContent(service: .apple, id: "1486333712", type: .track, location: nil),
                previewURL: URL(string: "https://audio-ssl.itunes.apple.com/preview/1486333712"),
                metadata: PlayableContentMetadata(duration: .seconds(200), position: 3)
            ),
            
            // Apple Music Album
            PlayableContent(
                title: "After Hours",
                subtitle: "The Weeknd",
                thumbnail: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/5e/a3/82/5ea3827e.jpg/300x300bb.jpg"),
                artwork: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/5e/a3/82/5ea3827e.jpg/1000x1000bb.jpg"),
                content: MediaContent(service: .apple, id: "1499378108", type: .album, location: nil),
            ),
            
            // Apple Music Library Track
            PlayableContent(
                title: "My Favorite Song",
                subtitle: "Various Artists",
                thumbnail: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music/generic.jpg/300x300bb.jpg"),
                artwork: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music/generic.jpg/1000x1000bb.jpg"),
                content: MediaContent(service: .apple, id: "i.abc123xyz", type: .libraryTrack, location: nil),
                metadata: PlayableContentMetadata(duration: .seconds(245), position: 5)
            ),
            
            // Plex Track
            PlayableContent(
                title: "Hotel California",
                subtitle: "Eagles",
                thumbnail: URL(string: "https://plex.tv/thumb/12345"),
                artwork: URL(string: "https://plex.tv/art/12345"),
                content: MediaContent(service: .plex, id: "/library/metadata/54321", type: .track, location: nil),
                metadata: PlayableContentMetadata(duration: .seconds(391), position: 1)
            ),
            
            // TuneIn Radio
            PlayableContent(
                title: "BBC Radio 1",
                subtitle: "Live Radio",
                thumbnail: URL(string: "https://cdn-profiles.tunein.com/s24939/images/logog.png"),
                artwork: URL(string: "https://cdn-profiles.tunein.com/s24939/images/logod.png"),
                content: MediaContent(service: .tuneIn, id: "s24939", type: .radio, location: nil),
            ),
            
            // Apple Music Radio
            PlayableContent(
                title: "Hits 1",
                subtitle: "Apple Music",
                thumbnail: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Features125/v4/48/8e/6f/488e6f52.png/300x300bb.jpg"),
                artwork: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Features125/v4/48/8e/6f/488e6f52.png/1000x1000bb.jpg"),
                content: MediaContent(service: .apple, id: "ra.978194965", type: .radio, location: nil),
            ),
            
            // SoundCloud Track
            PlayableContent(
                title: "Midnight Dreams",
                subtitle: "Independent Artist",
                thumbnail: URL(string: "https://i1.sndcdn.com/artworks-000123456789-abcdef-t500x500.jpg"),
                artwork: URL(string: "https://i1.sndcdn.com/artworks-000123456789-abcdef-original.jpg"),
                content: MediaContent(service: .soundcloud, id: "987654321", type: .track, location: nil),
                previewURL: URL(string: "https://api.soundcloud.com/tracks/987654321/stream"),
                metadata: PlayableContentMetadata(duration: .seconds(278), position: 1)
            )
        ]
    }
}
#endif
