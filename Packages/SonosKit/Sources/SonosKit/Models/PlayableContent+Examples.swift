import Foundation

#if DEBUG
public extension PlayableContent {
    static var harry: Self {
        PlayableContent(
            title: "Harry Styles",
            subtitle: "Harry Styles • 2017",
            thumbnail: URL(string:"https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/3d/5e/aa/3d5eaaa3-9a86-c264-5cd5-7fac83f99a59/886446451978.jpg/100x100bb.jpg"),
            artwork: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/3d/5e/aa/3d5eaaa3-9a86-c264-5cd5-7fac83f99a59/886446451978.jpg/600x600bb.jpg"),
            content: SonosKit.MediaContent(
                service: .apple,
                id: "1226034336",
                type: .album,
                location: URL(string:"https://music.apple.com/us/album/harry-styles/1226034336")
            ),
            previewURL: nil,
            metadata: SonosKit.PlayableContentMetadata(
                duration: nil,
                popularity: nil,
                artist: "Harry Styles",
                artistID: nil,
                album: nil,
                albumID: nil,
                albumYear: DateComponents(
                    calendar: .current,
                    year: 2017,
                    month: 5,
                    day: 12
                ).date,
                isrc: nil,
                position: nil,
                audioCodec: "",
                URIMetadata: nil,
                radioStation: nil,
                isPlayable: true,
                isExplicit: false,
                isSingle: false,
                fingerprint: nil,
                librarySectionID: nil
            )
        )
    }
    
    static var bazAlbum: Self {
        PlayableContent(
            title: "Music From Baz Luhrmann's Film The Great Gatsby (International Streaming Version)",
            subtitle: "Various Artists",
            thumbnail: URL(string:
                "https://i.scdn.co/image/ab67616d0000485174160d1c9ec851f7c4acaef1"
            ),
            artwork: URL(string:
                "https://i.scdn.co/image/ab67616d0000b27374160d1c9ec851f7c4acaef1"
            ),
            content: SonosKit.MediaContent(
                service: .spotify,
                id: "14uj0wJtd2M1570p6cXwn4",
                type: .album,
                location: nil
            ),
            previewURL: nil,
            metadata: nil
        )
    }
}
#endif
