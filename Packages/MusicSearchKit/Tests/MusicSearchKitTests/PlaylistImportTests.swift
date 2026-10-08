@testable import MusicSearchKit
import XCTest

final class PlaylistImportTests: XCTestCase {

    // MARK: - Links

    func testSpotifyPlaylistLinks() {
        let id = "37i9dQZF1DXcBWIGoYBM5M"
        XCTAssertEqual(PlaylistLink("https://open.spotify.com/playlist/\(id)?si=abc123"), .spotify(.playlist, id: id))
        XCTAssertEqual(PlaylistLink("https://open.spotify.com/intl-de/playlist/\(id)"), .spotify(.playlist, id: id))
        XCTAssertEqual(PlaylistLink("https://open.spotify.com/embed/playlist/\(id)"), .spotify(.playlist, id: id))
        XCTAssertEqual(PlaylistLink("https://open.spotify.com/user/spotify/playlist/\(id)"), .spotify(.playlist, id: id))
        XCTAssertEqual(PlaylistLink("spotify:playlist:\(id)"), .spotify(.playlist, id: id))
        XCTAssertEqual(PlaylistLink("spotify:user:someone:playlist:\(id)"), .spotify(.playlist, id: id))
        XCTAssertEqual(PlaylistLink("Check out this playlist on Spotify: https://open.spotify.com/playlist/\(id)"), .spotify(.playlist, id: id))
        XCTAssertEqual(PlaylistLink("https://open.spotify.com/album/6fmnT17jc2Sc69q3nza1eD"), .spotify(.album, id: "6fmnT17jc2Sc69q3nza1eD"))
    }

    func testSpotifySongLinksBecomeAList() {
        let text = """
        https://open.spotify.com/track/11hcBLPtbMp4aQI6zGQLub
        https://open.spotify.com/track/4EoJ151oQ5jY48z4RhSE96?si=x
        spotify:track:6A8OnjnpShshNpcqWtZRjr
        """
        XCTAssertEqual(PlaylistLink(text), .spotifyTracks(["11hcBLPtbMp4aQI6zGQLub", "4EoJ151oQ5jY48z4RhSE96", "6A8OnjnpShshNpcqWtZRjr"]))
    }

    func testSpotifyShortLink() {
        let url = URL(string: "https://spotify.link/AbCdEf123")!
        XCTAssertEqual(PlaylistLink(url.absoluteString), .spotifyShortLink(url))
    }

    func testAppleMusicLinks() {
        XCTAssertEqual(
            PlaylistLink("https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb"),
            .appleMusic(.playlist, id: "pl.f4d106fed2bd41149aaacabb233eb5eb", storefront: "us")
        )
        XCTAssertEqual(
            PlaylistLink("https://music.apple.com/gb/playlist/road-trip/pl.u-AkAmPlyUxXxXxX"),
            .appleMusic(.playlist, id: "pl.u-AkAmPlyUxXxXxX", storefront: "gb")
        )
        XCTAssertEqual(
            PlaylistLink("https://music.apple.com/us/album/true-blue/83447150?i=83447153"),
            .appleMusic(.album, id: "83447150", storefront: "us")
        )
        XCTAssertEqual(PlaylistLink("https://music.apple.com/library/playlist/p.abcDEF123"), .appleMusicLibrary(id: "p.abcDEF123"))
    }

    func testNotAPlaylist() {
        XCTAssertNil(PlaylistLink("hello"))
        XCTAssertNil(PlaylistLink("https://example.com/playlist/37i9dQZF1DXcBWIGoYBM5M"))
        XCTAssertNil(PlaylistLink("https://open.spotify.com/artist/06HL4z0CvFAxyc27GXpf02"))
    }

    // MARK: - Spotify embed

    private func embedPage(_ entity: String) -> String {
        """
        <html><head></head><body><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"state":{"data":{"entity":\(entity)}}}}}</script></body></html>
        """
    }

    func testReadsEmbedTrackList() throws {
        let html = embedPage("""
        {"type":"playlist","name":"All Out 80s","uri":"spotify:playlist:37i9dQZF1DX4UtSsGT1Sbe",
         "coverArt":{"sources":[{"url":"https://i.scdn.co/image/abc"}]},
         "trackList":[
          {"uri":"spotify:track:1","title":"Sweet Dreams (Are Made of This) - 2005 Remaster","subtitle":"Eurythmics,\\u00a0Annie Lennox,\\u00a0Dave Stewart","duration":216933,"entityType":"track"},
          {"uri":"spotify:track:2","title":"September","subtitle":"Earth, Wind & Fire","duration":215093,"entityType":"track"},
          {"uri":"spotify:episode:3","title":"A Podcast","subtitle":"Someone","duration":1000,"entityType":"episode"}
         ]}
        """)
        let entity = try SpotifyPlaylistReader.entity(in: html)
        XCTAssertEqual(entity.name, "All Out 80s")
        let tracks = SpotifyPlaylistReader.tracks(of: entity, album: nil)
        XCTAssertEqual(tracks.map(\.title), ["Sweet Dreams (Are Made of This) - 2005 Remaster", "September"])
        XCTAssertEqual(tracks[0].artists, ["Eurythmics", "Annie Lennox", "Dave Stewart"])
        XCTAssertEqual(tracks[1].artists, ["Earth, Wind & Fire"])
        XCTAssertEqual(tracks[0].duration ?? 0, 216.933, accuracy: 0.001)
        XCTAssertEqual(tracks.map(\.id), [0, 1])
    }

    func testReadsSingleSongEmbed() throws {
        let html = embedPage("""
        {"type":"track","name":"Patient Zero","title":"Patient Zero","uri":"spotify:track:11hcBLPtbMp4aQI6zGQLub",
         "artists":[{"name":"Taylor Swift"}],"duration":225868}
        """)
        let track = try XCTUnwrap(SpotifyPlaylistReader.track(SpotifyPlaylistReader.entity(in: html), index: 3))
        XCTAssertEqual(track.title, "Patient Zero")
        XCTAssertEqual(track.artists, ["Taylor Swift"])
        XCTAssertEqual(track.id, 3)
    }

    func testMissingPlaylistIsNotFound() {
        let html = """
        <script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"status":404,"title":"Page not found"}}}</script>
        """
        XCTAssertThrowsError(try SpotifyPlaylistReader.entity(in: html)) { error in
            XCTAssertEqual(error as? PlaylistImportError, .notFound)
        }
        XCTAssertThrowsError(try SpotifyPlaylistReader.entity(in: "<html></html>")) { error in
            XCTAssertEqual(error as? PlaylistImportError, .unreachable)
        }
    }

    // MARK: - Files

    func testExportifyCSV() throws {
        let csv = #"""
        "Track URI","Track Name","Artist URI(s)","Artist Name(s)","Album Name","Disc Number","Track Duration (ms)","ISRC"
        "spotify:track:4u7EnebtmKWzUH433cf5Qv","Bohemian Rhapsody - Remastered 2011","spotify:artist:1dfeR4HaWDbWqFHLkxsg1d","Queen","A Night At The Opera (2011 Remaster)","1","354320","GBUM71029604"
        "spotify:track:2","Under Pressure","spotify:artist:1,spotify:artist:2","Queen, David Bowie","Hot Space","1","248440",""
        "spotify:track:3","Say ""Hello""","spotify:artist:3","Someone","Album, With Comma","1","200000",""
        """#
        let playlist = try XCTUnwrap(PlaylistFileParser.parse(csv, fileName: "My Mix.csv"))
        XCTAssertEqual(playlist.name, "My Mix")
        XCTAssertEqual(playlist.source, .file)
        XCTAssertEqual(playlist.tracks.count, 3)
        XCTAssertEqual(playlist.tracks[0].title, "Bohemian Rhapsody - Remastered 2011")
        XCTAssertEqual(playlist.tracks[0].artists, ["Queen"])
        XCTAssertEqual(playlist.tracks[0].album, "A Night At The Opera (2011 Remaster)")
        XCTAssertEqual(playlist.tracks[0].duration ?? 0, 354.32, accuracy: 0.001)
        XCTAssertEqual(playlist.tracks[0].isrc, "GBUM71029604")
        XCTAssertEqual(playlist.tracks[0].sourceID, "spotify:track:4u7EnebtmKWzUH433cf5Qv")
        XCTAssertEqual(playlist.tracks[1].artists, ["Queen, David Bowie"])
        XCTAssertNil(playlist.tracks[1].isrc)
        XCTAssertEqual(playlist.tracks[2].title, "Say \"Hello\"")
        XCTAssertEqual(playlist.tracks[2].album, "Album, With Comma")
    }

    func testSemicolonCSVWithMinutes() throws {
        let csv = "Title;Artist;Album;Length\r\nYesterday;The Beatles;Help!;2:05\r\nHey Jude;The Beatles;;7:11\r\n"
        let tracks = try XCTUnwrap(PlaylistFileParser.parse(csv, fileName: "list.csv")?.tracks)
        XCTAssertEqual(tracks.map(\.title), ["Yesterday", "Hey Jude"])
        XCTAssertEqual(tracks.map(\.duration), [125, 431])
        XCTAssertNil(tracks[1].album)
    }

    func testCSVFieldWithLineBreak() {
        let rows = PlaylistFileParser.parseRows("a,b\n\"one\ntwo\",three\n", delimiter: ",")
        XCTAssertEqual(rows, [["a", "b"], ["one\ntwo", "three"]])
    }

    func testExtendedM3U() throws {
        let m3u = """
        #EXTM3U
        #PLAYLIST:Road Trip
        #EXTINF:354,Queen - Bohemian Rhapsody
        Music/Queen/A Night at the Opera/11 Bohemian Rhapsody.flac
        #EXTINF:-1,Under Pressure
        #EXTART:Queen & David Bowie
        Music/Queen/Hot%20Space/07%20Under%20Pressure.mp3
        Music/Eagles/Hotel California/01 - Eagles - Hotel California.mp3
        """
        let playlist = try XCTUnwrap(PlaylistFileParser.parse(m3u, fileName: "trip.m3u8"))
        XCTAssertEqual(playlist.name, "Road Trip")
        XCTAssertEqual(playlist.tracks.map(\.title), ["Bohemian Rhapsody", "Under Pressure", "Hotel California"])
        XCTAssertEqual(playlist.tracks.map(\.artists), [["Queen"], ["Queen & David Bowie"], ["Eagles"]])
        XCTAssertEqual(playlist.tracks.map(\.duration), [354, nil, nil])
    }

    func testPlainLines() throws {
        let text = """
        Queen - Bohemian Rhapsody
        Eagles – Hotel California

        Just A Title
        """
        let playlist = try XCTUnwrap(PlaylistFileParser.parse(text))
        XCTAssertEqual(playlist.name, "Imported Playlist")
        XCTAssertEqual(playlist.tracks.map(\.title), ["Bohemian Rhapsody", "Hotel California", "Just A Title"])
        XCTAssertEqual(playlist.tracks.map(\.artists), [["Queen"], ["Eagles"], []])
    }

    func testEmptyFileIsNothing() {
        XCTAssertNil(PlaylistFileParser.parse("", fileName: "empty.csv"))
        XCTAssertNil(PlaylistFileParser.parse("Track Name,Artist Name\n", fileName: "header.csv"))
    }

    func testDurations() {
        XCTAssertEqual(PlaylistFileParser.duration("225868", milliseconds: true), 225.868)
        XCTAssertEqual(PlaylistFileParser.duration("225868", milliseconds: false), 225.868)
        XCTAssertEqual(PlaylistFileParser.duration("225", milliseconds: false), 225)
        XCTAssertEqual(PlaylistFileParser.duration("1:02:03", milliseconds: false), 3723)
        XCTAssertNil(PlaylistFileParser.duration("soon", milliseconds: false))
    }

    func testUnreadCount() {
        let tracks = (0..<100).map { ImportedTrack(id: $0, title: "Song \($0)", artists: []) }
        XCTAssertEqual(ImportedPlaylist(name: "x", source: .spotify, tracks: tracks, totalCount: 150).unreadCount, 50)
        XCTAssertEqual(ImportedPlaylist(name: "x", source: .spotify, tracks: tracks).unreadCount, 0)
    }
}
