import XCTest
@testable import SonosKit

/// The index the Files provider builds over its tracks: grouping into
/// albums and artists, play order, the offered sorts, playlists and search.
@MainActor
final class FilesLibraryIndexTests: XCTestCase {

    private let root = URL(fileURLWithPath: "/Music", isDirectory: true)

    private func track(
        _ path: String, title: String, artist: String? = nil, albumArtist: String? = nil, album: String? = nil,
        year: Int? = nil, trackNumber: Int? = nil, discNumber: Int? = nil, duration: Double? = nil,
        modified: TimeInterval? = nil, downloaded: Bool = true
    ) -> FileTrack {
        FileTrack(
            relativePath: path, title: title, artist: artist, albumArtist: albumArtist, album: album,
            year: year, trackNumber: trackNumber, discNumber: discNumber, duration: duration,
            fileExtension: URL(fileURLWithPath: path).pathExtension.lowercased(),
            isDownloaded: downloaded,
            modificationDate: modified.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private func library() -> FilesLibraryService {
        FilesLibraryService(tracks: [
            track("R/OK/01.mp3", title: "Airbag", artist: "Radiohead", album: "OK Computer", year: 1997, trackNumber: 1, duration: 284, modified: 100),
            track("R/OK/02.mp3", title: "Paranoid Android", artist: "Radiohead", album: "OK Computer", year: 1997, trackNumber: 2, duration: 383, modified: 300),
            track("R/KidA/01.mp3", title: "Everything In Its Right Place", artist: "Radiohead", album: "Kid A", year: 2000, trackNumber: 1, duration: 251, modified: 200),
            track("B/White/D2/01.mp3", title: "Birthday", artist: "The Beatles", album: "The White Album", year: 1968, trackNumber: 1, discNumber: 2, duration: 162, modified: 50),
            track("B/White/D1/01.mp3", title: "Back in the U.S.S.R.", artist: "The Beatles", album: "The White Album", year: 1968, trackNumber: 1, discNumber: 1, duration: 163, modified: 60),
            track("V/Comp/03.mp3", title: "Guest Song", artist: "Some Guest", albumArtist: "Various Artists", album: "Now That's Music", trackNumber: 3, duration: 200, modified: 400),
            track("V/Comp/01.mp3", title: "Other Guest", artist: "Another Guest", albumArtist: "Various Artists", album: "Now That's Music", trackNumber: 1, duration: 210, modified: 400),
            track("cloud.mp3", title: "Still In iCloud", artist: "Cloud", album: "Cloud", downloaded: false),
        ], playlists: [
            FilePlaylist(relativePath: "Playlists/Mix.m3u", title: "Mix", trackRelativePaths: ["R/KidA/01.mp3", "B/White/D2/01.mp3", "missing.mp3"]),
            FilePlaylist(relativePath: "Playlists/Empty.m3u", title: "Empty", trackRelativePaths: []),
        ], folderURL: root)
    }

    func testAlbumsGroupByAlbumArtistSoCompilationsStayOneAlbum() {
        let library = library()
        XCTAssertEqual(library.albums.map(\.title), ["Cloud", "Kid A", "Now That's Music", "OK Computer", "The White Album"])
        XCTAssertEqual(library.artists.map(\.title), ["Cloud", "Radiohead", "The Beatles", "Various Artists"])
        let compilation = library.albums.first { $0.title == "Now That's Music" }!
        XCTAssertEqual(compilation.metadata?.artist, "Various Artists")
        XCTAssertEqual(library.albumTracks(albumID: compilation.content.id).map(\.title), ["Other Guest", "Guest Song"])
        XCTAssertEqual(library.albumTracks(albumID: compilation.content.id).first?.metadata?.artist, "Another Guest",
                       "A song keeps its own artist even when the album is credited to another")
    }

    func testAlbumTracksOrderByDiscThenTrack() {
        let library = library()
        let white = library.albums.first { $0.title == "The White Album" }!
        XCTAssertEqual(library.albumTracks(albumID: white.content.id).map(\.title), ["Back in the U.S.S.R.", "Birthday"])
    }

    func testArtistAlbumsAndTracks() {
        let library = library()
        let radiohead = library.artists.first { $0.title == "Radiohead" }!
        XCTAssertEqual(library.artistAlbums(artistID: radiohead.content.id).map(\.title), ["Kid A", "OK Computer"])
        XCTAssertEqual(library.artistTracks(artistID: radiohead.content.id).map(\.title),
                       ["Everything In Its Right Place", "Airbag", "Paranoid Android"])
    }

    func testSongsCarryFileURLYearAndPlayability() {
        let library = library()
        let airbag = library.songs.first { $0.title == "Airbag" }!
        XCTAssertEqual(airbag.content.service, .files)
        XCTAssertEqual(airbag.content.location, root.appendingPathComponent("R/OK/01.mp3"))
        XCTAssertEqual(airbag.previewURL, airbag.content.location)
        XCTAssertEqual(airbag.metadata?.position, 1)
        XCTAssertEqual(airbag.metadata?.album, "OK Computer")
        XCTAssertEqual(airbag.metadata?.audioCodec, "mp3")
        XCTAssertEqual(airbag.subtitle, "Radiohead • MP3")
        XCTAssertEqual(airbag.metadata?.duration, .seconds(284))
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.year, from: airbag.metadata!.albumYear!), 1997)
        XCTAssertEqual(airbag.metadata?.isPlayable, true)

        let cloud = library.songs.first { $0.title == "Still In iCloud" }!
        XCTAssertEqual(cloud.metadata?.isPlayable, false, "A placeholder lists but can't play until it downloads")
    }

    func testSongSorts() {
        let library = library()
        XCTAssertEqual(library.songs(sortedBy: .title, offset: 0).first?.title, "Airbag")
        XCTAssertEqual(library.songs(sortedBy: .title, descending: true, offset: 0).first?.title, "Still In iCloud")
        XCTAssertEqual(library.songs(sortedBy: .duration, descending: true, offset: 0).first?.title, "Paranoid Android")
        XCTAssertEqual(Set(library.songs(sortedBy: .recentlyAdded, descending: true, offset: 0).map(\.title).prefix(2)),
                       ["Guest Song", "Other Guest"], "The two newest files share a date")
        XCTAssertEqual(library.songs(sortedBy: .recentlyAdded, offset: 0).first?.title, "Still In iCloud",
                       "No date sorts as oldest")
        // Album order falls back to track number inside an album.
        XCTAssertEqual(library.songs(sortedBy: .album, offset: 0).map(\.title).prefix(4),
                       ["Still In iCloud", "Everything In Its Right Place", "Other Guest", "Guest Song"])
        // Artist order is artist, then title.
        XCTAssertEqual(library.songs(sortedBy: .artist, offset: 0).map(\.title).prefix(2), ["Other Guest", "Still In iCloud"])
    }

    func testSongPagingIsASliceOfTheSortedList() {
        let library = library()
        let all = library.songs(sortedBy: .title, offset: 0, limit: 100)
        XCTAssertEqual(library.songs(sortedBy: .title, offset: 2, limit: 3), Array(all[2..<5]))
        XCTAssertEqual(library.songs(sortedBy: .title, offset: 100), [])
        XCTAssertEqual(library.songs(sortedBy: .title, offset: -5, limit: 1), [all[0]], "A negative offset reads from the start")
    }

    func testAlbumSorts() {
        let library = library()
        XCTAssertEqual(library.albums(sortedBy: .year, descending: true).map(\.title),
                       ["Kid A", "OK Computer", "The White Album", "Now That's Music", "Cloud"],
                       "Newest year first; albums with no year sort last, their title tie reversed too")
        XCTAssertEqual(library.albums(sortedBy: .recentlyAdded, descending: true).first?.title, "Now That's Music")
        XCTAssertEqual(library.recentlyAddedAlbums(limit: 2).map(\.title), ["Now That's Music", "OK Computer"])
        XCTAssertEqual(library.albums(sortedBy: .artist).first?.metadata?.artist, "Cloud")
    }

    func testPlaylistsKeepFileOrderAndDropUnknownFiles() {
        let library = library()
        XCTAssertEqual(library.playlists.map(\.title), ["Empty", "Mix"])
        let mix = library.playlists.first { $0.title == "Mix" }!
        XCTAssertEqual(mix.subtitle, "2 songs")
        XCTAssertEqual(library.playlistTracks(playlistID: mix.content.id).map(\.title), ["Everything In Its Right Place", "Birthday"])
        XCTAssertEqual(mix.content.location, root.appendingPathComponent("Playlists/Mix.m3u"))
        let empty = library.playlists.first { $0.title == "Empty" }!
        XCTAssertEqual(empty.subtitle, "Empty")
        XCTAssertEqual(library.playlistTracks(playlistID: empty.content.id), [])
    }

    func testAllSongsContainerIsTheWholeLibrary() {
        let library = library()
        XCTAssertEqual(library.playlist(id: FilesLibraryService.allSongsID)?.title, "All Songs")
        XCTAssertEqual(library.playlistTracks(playlistID: FilesLibraryService.allSongsID), library.songs)
    }

    func testLookupsByID() {
        let library = library()
        let song = library.songs[0]
        XCTAssertEqual(library.track(id: song.content.id), song)
        XCTAssertEqual(library.album(id: song.metadata!.albumID!)?.title, song.metadata?.album)
        XCTAssertEqual(library.artist(id: song.metadata!.artistID!)?.title, song.metadata?.artist)
        XCTAssertNil(library.track(id: "nope"))
        XCTAssertEqual(library.song(atRelativePath: "R/OK/01.mp3")?.title, "Airbag")
    }

    func testSearchMatchesTitleSubtitleAndAlbumAcrossKinds() {
        let library = library()
        let hits = library.search(query: "radiohead")
        XCTAssertEqual(hits.first?.content.type, .artist, "Artists come first, then albums, playlists and songs")
        XCTAssertTrue(hits.contains { $0.title == "OK Computer" })
        XCTAssertTrue(hits.contains { $0.title == "Airbag" })
        XCTAssertEqual(library.search(query: "  ").count, 0)
        XCTAssertEqual(library.search(query: "kid a").map(\.title), ["Kid A", "Everything In Its Right Place"])
    }

    func testIDsAreStableAcrossRebuilds() {
        let a = library()
        let b = library()
        XCTAssertEqual(a.songs.map(\.content.id), b.songs.map(\.content.id))
        XCTAssertEqual(a.albums.map(\.content.id), b.albums.map(\.content.id))
        XCTAssertEqual(a.playlists.map(\.content.id), b.playlists.map(\.content.id))
    }

    func testUntaggedTrackFallsToUnknownArtistAndAlbum() {
        let library = FilesLibraryService(tracks: [track("loose.mp3", title: "Loose")], folderURL: root)
        XCTAssertEqual(library.albums.map(\.title), ["Unknown Album"])
        XCTAssertEqual(library.artists.map(\.title), ["Unknown Artist"])
        XCTAssertEqual(library.songs.first?.subtitle, "Unknown Artist • MP3")
    }
}
