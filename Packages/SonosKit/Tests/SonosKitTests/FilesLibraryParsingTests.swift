import XCTest
@testable import SonosKit

/// The Files provider's pure parsing: what a file's name and folders say
/// about it, how `.m3u` playlists are read and written, and which files a
/// rescan can skip. Nothing here opens an audio file.
final class FilesLibraryParsingTests: XCTestCase {

    private let root = URL(fileURLWithPath: "/Music", isDirectory: true)

    private func track(_ relativePath: String) -> FileTrack {
        FileTrack(
            relativePath: relativePath,
            title: URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent,
            fileExtension: URL(fileURLWithPath: relativePath).pathExtension.lowercased(),
            isDownloaded: true
        )
    }

    // MARK: - Folder layout

    func testArtistAlbumFolderLayoutFillsMissingTags() {
        var track = track("Radiohead/OK Computer/03 Karma Police.mp3")
        FilesLibraryService.applyFolderLayout(
            to: &track, url: root.appendingPathComponent(track.relativePath), root: root, titleFromFileName: true
        )
        XCTAssertEqual(track.artist, "Radiohead")
        XCTAssertEqual(track.album, "OK Computer")
        XCTAssertEqual(track.trackNumber, 3)
        XCTAssertEqual(track.title, "Karma Police")
        XCTAssertNil(track.discNumber)
    }

    func testTagsWinOverFolderLayout() {
        var track = track("Misc/Rips/03 Karma Police.mp3")
        track.artist = "Tagged Artist"
        track.album = "Tagged Album"
        track.title = "Tagged Title"
        track.trackNumber = 9
        FilesLibraryService.applyFolderLayout(
            to: &track, url: root.appendingPathComponent(track.relativePath), root: root, titleFromFileName: false
        )
        XCTAssertEqual(track.artist, "Tagged Artist")
        XCTAssertEqual(track.album, "Tagged Album")
        XCTAssertEqual(track.title, "Tagged Title")
        XCTAssertEqual(track.trackNumber, 9)
    }

    func testDiscFolderNamesTheDiscNotTheAlbum() {
        var track = track("Beatles/White Album/Disc 2/01 Birthday.mp3")
        FilesLibraryService.applyFolderLayout(
            to: &track, url: root.appendingPathComponent(track.relativePath), root: root, titleFromFileName: true
        )
        XCTAssertEqual(track.artist, "Beatles")
        XCTAssertEqual(track.album, "White Album")
        XCTAssertEqual(track.discNumber, 2)
        XCTAssertEqual(track.trackNumber, 1)
        XCTAssertEqual(track.title, "Birthday")
    }

    func testDiscTrackFileNamePrefix() {
        var track = track("Artist/Album/2-05 Song.flac")
        FilesLibraryService.applyFolderLayout(
            to: &track, url: root.appendingPathComponent(track.relativePath), root: root, titleFromFileName: true
        )
        XCTAssertEqual(track.discNumber, 2)
        XCTAssertEqual(track.trackNumber, 5)
        XCTAssertEqual(track.title, "Song")
    }

    func testFileNameSeparators() {
        for name in ["03 - Title", "03. Title", "03) Title", "03 . Title", "3 Title"] {
            var track = track("A/B/\(name).mp3")
            FilesLibraryService.applyFolderLayout(
                to: &track, url: root.appendingPathComponent(track.relativePath), root: root, titleFromFileName: true
            )
            XCTAssertEqual(track.trackNumber, 3, name)
            XCTAssertEqual(track.title, "Title", name)
        }
    }

    func testFileAtRootHasNoArtistOrAlbumFromLayout() {
        var track = track("Loose Song.mp3")
        FilesLibraryService.applyFolderLayout(
            to: &track, url: root.appendingPathComponent(track.relativePath), root: root, titleFromFileName: true
        )
        XCTAssertNil(track.artist)
        XCTAssertNil(track.album)
        XCTAssertNil(track.trackNumber)
        XCTAssertEqual(track.title, "Loose Song")
    }

    func testAlbumArtistBlocksArtistFromFolder() {
        var track = track("Various/Compilation/01 Song.mp3")
        track.albumArtist = "Various Artists"
        FilesLibraryService.applyFolderLayout(
            to: &track, url: root.appendingPathComponent(track.relativePath), root: root, titleFromFileName: true
        )
        XCTAssertNil(track.artist, "A tagged album artist means the folder is not the track artist")
        XCTAssertEqual(track.album, "Compilation")
    }

    func testDiscNumberFromFolder() {
        XCTAssertEqual(FilesLibraryService.discNumber(fromFolder: "Disc 2"), 2)
        XCTAssertEqual(FilesLibraryService.discNumber(fromFolder: "CD1"), 1)
        XCTAssertEqual(FilesLibraryService.discNumber(fromFolder: "disk 03"), 3)
        XCTAssertNil(FilesLibraryService.discNumber(fromFolder: "Discography"))
        XCTAssertNil(FilesLibraryService.discNumber(fromFolder: "Disc 200"))
    }

    // MARK: - Tag values

    func testYearFromDateStrings() {
        XCTAssertEqual(FilesLibraryService.year(from: "1997"), 1997)
        XCTAssertEqual(FilesLibraryService.year(from: "2004-03-09T00:00:00Z"), 2004)
        XCTAssertEqual(FilesLibraryService.year(from: "Released 2011"), 2011)
        XCTAssertNil(FilesLibraryService.year(from: "20110"), "A five-digit run is not a year")
        XCTAssertNil(FilesLibraryService.year(from: "1066"), "Out of range")
        XCTAssertNil(FilesLibraryService.year(from: "no year here"))
    }

    func testPackedNumberFromID3AndITunes() {
        XCTAssertEqual(FilesLibraryService.packedNumber(from: "3/12" as NSString), 3)
        XCTAssertEqual(FilesLibraryService.packedNumber(from: " 7 " as NSString), 7)
        XCTAssertEqual(FilesLibraryService.packedNumber(from: NSNumber(value: 11)), 11)
        // iTunes packs the number into bytes 2–3 of an 8-byte blob.
        let packed = Data([0, 0, 0x01, 0x02, 0, 0, 0, 0]) as NSData
        XCTAssertEqual(FilesLibraryService.packedNumber(from: packed), 0x0102)
        XCTAssertNil(FilesLibraryService.packedNumber(from: Data([0, 0, 0, 0]) as NSData))
        XCTAssertNil(FilesLibraryService.packedNumber(from: "abc" as NSString))
    }

    func testNonEmptyTrims() {
        XCTAssertEqual(FilesLibraryService.nonEmpty("  Artist \n"), "Artist")
        XCTAssertNil(FilesLibraryService.nonEmpty("   "))
        XCTAssertNil(FilesLibraryService.nonEmpty(nil))
    }

    // MARK: - Paths

    func testRelativePathInsideAndOutsideRoot() {
        XCTAssertEqual(FilesLibraryService.relativePath(of: root.appendingPathComponent("A/B/c.mp3"), in: root), "A/B/c.mp3")
        XCTAssertEqual(FilesLibraryService.relativePath(of: URL(fileURLWithPath: "/Elsewhere/c.mp3"), in: root), "c.mp3")
    }

    func testRelativePathBetweenFolders() {
        XCTAssertEqual(FilesLibraryService.relativePath(from: "Playlists", to: "Artist/Album/01 Song.mp3"), "../Artist/Album/01 Song.mp3")
        XCTAssertEqual(FilesLibraryService.relativePath(from: "", to: "Song.mp3"), "Song.mp3")
        XCTAssertEqual(FilesLibraryService.relativePath(from: "Artist/Album", to: "Artist/Album/01 Song.mp3"), "01 Song.mp3")
        XCTAssertEqual(FilesLibraryService.relativePath(from: "Artist/Album", to: "Artist/Other/02.mp3"), "../Other/02.mp3")
    }

    func testHashIsStableAndShort() {
        XCTAssertEqual(FilesLibraryService.hash("song|a.mp3"), FilesLibraryService.hash("song|a.mp3"))
        XCTAssertNotEqual(FilesLibraryService.hash("song|a.mp3"), FilesLibraryService.hash("song|b.mp3"))
        XCTAssertEqual(FilesLibraryService.hash("x").count, 16)
    }

    // MARK: - Rescan partition

    func testRescanKeepsUnchangedFilesAndRereadsTheRest() {
        let date = Date(timeIntervalSince1970: 1_000)
        var unchanged = track("A/unchanged.mp3")
        unchanged.modificationDate = date
        unchanged.fileSize = 10
        unchanged.title = "Kept Title"
        var resized = track("A/resized.mp3")
        resized.modificationDate = date
        resized.fileSize = 10
        var placeholder = track("A/was-in-cloud.mp3")
        placeholder.isDownloaded = false
        placeholder.modificationDate = date
        placeholder.fileSize = 10
        let previous = Dictionary(uniqueKeysWithValues: [unchanged, resized, placeholder].map { ($0.relativePath, $0) })

        let entries: [FilesLibraryService.FolderWalk.Entry] = [
            .init(url: root.appendingPathComponent("A/unchanged.mp3"), modificationDate: date, fileSize: 10),
            .init(url: root.appendingPathComponent("A/resized.mp3"), modificationDate: date, fileSize: 11),
            .init(url: root.appendingPathComponent("A/was-in-cloud.mp3"), modificationDate: date, fileSize: 10),
            .init(url: root.appendingPathComponent("A/new.mp3"), modificationDate: date, fileSize: 5),
        ]
        let (kept, toRead) = FilesLibraryService.partitionForRescan(entries, previous: previous, root: root)

        XCTAssertEqual(kept.map(\.relativePath), ["A/unchanged.mp3"])
        XCTAssertEqual(kept.first?.title, "Kept Title", "An unchanged file keeps its tags without a re-read")
        XCTAssertEqual(toRead.map { FilesLibraryService.relativePath(of: $0.url, in: root) },
                       ["A/resized.mp3", "A/was-in-cloud.mp3", "A/new.mp3"])
    }

    // MARK: - M3U

    func testM3UTextIsExtendedAndRelativeToThePlaylist() {
        var song = track("Artist/Album/01 Song.mp3")
        song.title = "Song"
        song.artist = "Artist"
        song.duration = 187.6
        let playlist = FilePlaylist(
            relativePath: "Playlists/Mix.m3u",
            title: "Road Mix",
            trackRelativePaths: ["Artist/Album/01 Song.mp3", "Unknown/02.mp3"]
        )
        let text = FilesLibraryService.m3uText(for: playlist, tracksByPath: [song.relativePath: song])
        XCTAssertEqual(text, """
        #EXTM3U
        #PLAYLIST:Road Mix
        #EXTINF:188,Artist - Song
        ../Artist/Album/01 Song.mp3
        ../Unknown/02.mp3

        """)
    }

    func testM3UWithoutDurationWritesMinusOne() {
        var song = track("a.mp3")
        song.title = "A"
        song.albumArtist = "Band"
        let playlist = FilePlaylist(relativePath: "list.m3u", title: "L", trackRelativePaths: ["a.mp3"])
        let text = FilesLibraryService.m3uText(for: playlist, tracksByPath: ["a.mp3": song])
        XCTAssertTrue(text.contains("#EXTINF:-1,Band - A\na.mp3\n"), text)
    }

    func testReadPlaylistsResolvesRelativeAbsoluteAndForeignPaths() throws {
        let folder = try makeTempFolder()
        let playlists = folder.appendingPathComponent("Playlists", isDirectory: true)
        try FileManager.default.createDirectory(at: playlists, withIntermediateDirectories: true)
        let contents = """
        #EXTM3U
        #PLAYLIST:Named In File
        #EXTINF:1,skip me

        ../Artist/Album/01 Song.mp3
        \(folder.path)/Artist/Album/02 Song.mp3
        /Volumes/OtherMac/Music/Artist/Album/03 Song.mp3
        ../Artist/Album/01 Song.mp3
        ../Missing/nope.mp3
        """
        try contents.write(to: playlists.appendingPathComponent("Mix.m3u"), atomically: true, encoding: .utf8)
        let known: Set<String> = ["Artist/Album/01 Song.mp3", "Artist/Album/02 Song.mp3", "Artist/Album/03 Song.mp3"]

        let read = FilesLibraryService.readPlaylists([playlists.appendingPathComponent("Mix.m3u")], root: folder, knownPaths: known)

        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read.first?.relativePath, "Playlists/Mix.m3u")
        XCTAssertEqual(read.first?.title, "Named In File")
        XCTAssertEqual(read.first?.trackRelativePaths, [
            "Artist/Album/01 Song.mp3",
            "Artist/Album/02 Song.mp3",
            "Artist/Album/03 Song.mp3",
        ], "Relative, absolute and foreign-machine paths resolve; duplicates and unknown files drop")
    }

    func testReadPlaylistsTitleFallsBackToFileNameAndKeepsEmptyLists() throws {
        let folder = try makeTempFolder()
        try "#EXTM3U\n".write(to: folder.appendingPathComponent("Empty.m3u"), atomically: true, encoding: .utf8)
        let read = FilesLibraryService.readPlaylists([folder.appendingPathComponent("Empty.m3u")], root: folder, knownPaths: [])
        XCTAssertEqual(read.first?.title, "Empty")
        XCTAssertEqual(read.first?.trackRelativePaths, [])
    }

    func testReadPlaylistsAcceptsLatin1() throws {
        let folder = try makeTempFolder()
        let latin1 = "#PLAYLIST:Caf\u{e9}\nsong.mp3\n".data(using: .isoLatin1)!
        try latin1.write(to: folder.appendingPathComponent("l.m3u"))
        let read = FilesLibraryService.readPlaylists([folder.appendingPathComponent("l.m3u")], root: folder, knownPaths: ["song.mp3"])
        XCTAssertEqual(read.first?.title, "Café")
        XCTAssertEqual(read.first?.trackRelativePaths, ["song.mp3"])
    }

    // MARK: - Walking a folder

    func testWalkFindsAudioPlaylistsAndPlaceholdersAndSkipsHidden() throws {
        let folder = try makeTempFolder()
        let fm = FileManager.default
        try fm.createDirectory(at: folder.appendingPathComponent("Artist/Album"), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        try Data([0]).write(to: folder.appendingPathComponent("Artist/Album/01 Song.mp3"))
        try Data([0]).write(to: folder.appendingPathComponent("Artist/Album/02 Song.FLAC"))
        try Data([0]).write(to: folder.appendingPathComponent("Artist/Album/cover.jpg"))
        try Data([0]).write(to: folder.appendingPathComponent("Artist/Album/.03 Song.m4a.icloud"))
        try Data([0]).write(to: folder.appendingPathComponent("Artist/Album/.notes.txt.icloud"))
        try Data([0]).write(to: folder.appendingPathComponent(".hidden/secret.mp3"))
        try "#EXTM3U\n".write(to: folder.appendingPathComponent("Mix.m3u8"), atomically: true, encoding: .utf8)

        let walk = FilesLibraryService.walkFolder(folder)

        let files = Set(walk.files.map { FilesLibraryService.relativePath(of: $0.url, in: folder) })
        XCTAssertEqual(files, ["Artist/Album/01 Song.mp3", "Artist/Album/02 Song.FLAC"])
        XCTAssertEqual(walk.files.first?.fileSize, 1)
        XCTAssertNotNil(walk.files.first?.modificationDate)
        XCTAssertEqual(walk.placeholders.map { FilesLibraryService.relativePath(of: $0, in: folder) }, ["Artist/Album/03 Song.m4a"])
        XCTAssertEqual(walk.playlists.map { FilesLibraryService.relativePath(of: $0, in: folder) }, ["Mix.m3u8"])
    }

    // MARK: - Helpers

    private func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilesLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.standardizedFileURL
    }
}
