import AVFoundation
import CryptoKit
import Defaults
import Foundation
import Observation

/// One audio file in the picked folder, as read from its tags. Kept on disk
/// between launches so the library is there before a rescan.
struct FileTrack: Codable, Sendable, Hashable {
    /// Path under the picked folder — the stable identity of the file, since
    /// the folder's own URL can change between launches.
    var relativePath: String
    var title: String
    var artist: String?
    var albumArtist: String?
    var album: String?
    var trackNumber: Int?
    var discNumber: Int?
    /// Seconds.
    var duration: Double?
    /// The embedded cover, written once per album into the artwork cache.
    var artworkFileName: String?
    var fileExtension: String
    /// False for an iCloud Drive file that is still only a placeholder; its
    /// tags are read on the next scan once it has downloaded.
    var isDownloaded: Bool

    /// The credited artist for grouping: the album artist where the tags
    /// have one, so a compilation stays one album.
    var groupingArtist: String {
        let candidate = albumArtist?.trimmingCharacters(in: .whitespaces) ?? ""
        if !candidate.isEmpty { return candidate }
        let single = artist?.trimmingCharacters(in: .whitespaces) ?? ""
        return single.isEmpty ? "Unknown Artist" : single
    }

    var albumTitle: String {
        let name = album?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Unknown Album" : name
    }
}

/// The Files provider: audio files in one folder the user picked, on this
/// device or in iCloud Drive. The folder is held as a security-scoped
/// bookmark, walked for audio files, and each file's tags are read with
/// AVFoundation into songs, albums and artists. Nothing leaves the device —
/// there is no account and no server — so its tracks play on this device
/// only (`MusicService.playsOnDeviceOnly`), off their file URLs.
///
/// iCloud Drive folders can hold files that aren't downloaded yet. Those
/// appear as hidden `.name.ext.icloud` placeholders; a scan asks the system
/// to download them and lists them by file name until the next scan can read
/// their tags.
@MainActor
@Observable
public final class FilesLibraryService {
    public static let shared = FilesLibraryService()

    public private(set) var songs: [PlayableContent] = []
    public private(set) var albums: [PlayableContent] = []
    public private(set) var artists: [PlayableContent] = []

    public private(set) var isScanning = false
    /// Files whose tags have been read in the running scan.
    public private(set) var scannedCount = 0
    /// Files the running scan found, once it has walked the folder.
    public private(set) var foundCount = 0
    /// iCloud placeholders the last scan asked the system to download.
    public private(set) var pendingDownloadCount = 0
    public private(set) var lastScan: Date?
    public private(set) var lastError: String?
    /// The picked folder's name, for the rows that describe the provider.
    public private(set) var folderName: String?

    /// Whether a folder has been picked at all.
    public var isConfigured: Bool { folderName != nil }

    /// Whether the folder is in iCloud Drive, for the copy that explains
    /// placeholders.
    public var isCloudFolder: Bool {
        guard let folderURL else { return false }
        return (try? folderURL.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) ?? false
    }

    @ObservationIgnored private var folderURL: URL?
    @ObservationIgnored private var isAccessingFolder = false
    @ObservationIgnored private var tracks: [FileTrack] = []
    @ObservationIgnored private var songsByID: [String: PlayableContent] = [:]
    @ObservationIgnored private var albumsByID: [String: PlayableContent] = [:]
    @ObservationIgnored private var artistsByID: [String: PlayableContent] = [:]
    @ObservationIgnored private var songIDsByAlbum: [String: [String]] = [:]
    @ObservationIgnored private var albumIDsByArtist: [String: [String]] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard

    nonisolated private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aif", "aiff", "aifc", "caf", "m4b", "alac"
    ]

    private init() {
        folderName = defaults.string(forKey: AppStorageKeys.filesFolderName)
        resolveFolder()
        tracks = Self.loadIndex()
        rebuildIndex()
    }

    // MARK: - Folder

    /// Keeps the picked folder. `url` is the security-scoped URL a document
    /// picker hands over; the bookmark is what survives a relaunch.
    public func setFolder(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let bookmark = try url.bookmarkData(
                options: Self.bookmarkCreationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmark, forKey: AppStorageKeys.filesFolderBookmark)
            defaults.set(url.lastPathComponent, forKey: AppStorageKeys.filesFolderName)
            folderName = url.lastPathComponent
            lastError = nil
        } catch {
            lastError = "Couldn't keep access to that folder: \(error.localizedDescription)"
            return
        }

        stopAccessingFolder()
        tracks = []
        rebuildIndex()
        resolveFolder()
        rescan()
    }

    /// Forgets the folder and everything indexed from it.
    public func removeFolder() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        stopAccessingFolder()
        folderURL = nil
        folderName = nil
        lastError = nil
        lastScan = nil
        pendingDownloadCount = 0
        tracks = []
        rebuildIndex()
        defaults.removeObject(forKey: AppStorageKeys.filesFolderBookmark)
        defaults.removeObject(forKey: AppStorageKeys.filesFolderName)
        try? FileManager.default.removeItem(at: Self.indexURL)
        try? FileManager.default.removeItem(at: Self.artworkDirectory)
    }

    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS) || targetEnvironment(macCatalyst)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS) || targetEnvironment(macCatalyst)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    /// Turns the stored bookmark back into a URL and opens access to it for
    /// the life of the process — the index's file URLs, and the player
    /// reading them, are only valid while it is open.
    private func resolveFolder() {
        guard let bookmark = defaults.data(forKey: AppStorageKeys.filesFolderBookmark) else { return }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: Self.bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            folderURL = url
            isAccessingFolder = url.startAccessingSecurityScopedResource()
            if isStale, let fresh = try? url.bookmarkData(
                options: Self.bookmarkCreationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                defaults.set(fresh, forKey: AppStorageKeys.filesFolderBookmark)
            }
        } catch {
            lastError = "The folder can't be opened any more. Choose it again."
        }
    }

    private func stopAccessingFolder() {
        if isAccessingFolder, let folderURL {
            folderURL.stopAccessingSecurityScopedResource()
        }
        isAccessingFolder = false
    }

    // MARK: - Scanning

    /// Scans when there is a folder but nothing indexed yet — what the browse
    /// screens and search call before reading.
    public func scanIfNeeded() async {
        guard isConfigured, tracks.isEmpty, !isScanning else { return }
        await scan()
    }

    /// Starts a fresh scan, replacing any running one.
    public func rescan() {
        scanTask?.cancel()
        scanTask = Task { await scan() }
    }

    public func scan() async {
        guard let folderURL else { return }
        guard !isScanning else { return }
        isScanning = true
        scannedCount = 0
        foundCount = 0
        defer { isScanning = false }

        let root = folderURL
        let artworkDirectory = Self.artworkDirectory
        try? FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)

        // Walking a big folder is file I/O; keep it off the main actor.
        let walk = await Task.detached(priority: .userInitiated) {
            Self.audioFiles(in: root)
        }.value
        guard !Task.isCancelled else { return }
        foundCount = walk.files.count + walk.placeholders.count
        pendingDownloadCount = walk.placeholders.count

        // Tags are read a few files at a time: AVFoundation opens each file,
        // and a folder can hold thousands.
        var read: [FileTrack] = []
        var next = 0
        let files = walk.files
        await withTaskGroup(of: FileTrack?.self) { group in
            let width = min(4, files.count)
            while next < width {
                let url = files[next]
                next += 1
                group.addTask { await Self.readTrack(at: url, root: root, artworkDirectory: artworkDirectory) }
            }
            while let result = await group.next() {
                if let result { read.append(result) }
                scannedCount += 1
                if Task.isCancelled { group.cancelAll() }
                if next < files.count, !Task.isCancelled {
                    let url = files[next]
                    next += 1
                    group.addTask { await Self.readTrack(at: url, root: root, artworkDirectory: artworkDirectory) }
                }
            }
        }
        guard !Task.isCancelled else { return }

        // Placeholders are listed by name until they download.
        let placeholders = walk.placeholders.map { url -> FileTrack in
            FileTrack(
                relativePath: Self.relativePath(of: url, in: root),
                title: url.deletingPathExtension().lastPathComponent,
                fileExtension: url.pathExtension.lowercased(),
                isDownloaded: false
            )
        }

        tracks = (read + placeholders).sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        lastScan = .now
        rebuildIndex()
        Self.saveIndex(tracks)
    }

    private struct FolderWalk: Sendable {
        var files: [URL] = []
        var placeholders: [URL] = []
    }

    /// Every audio file under `root`. iCloud placeholders (`.name.ext.icloud`)
    /// are asked to download and reported separately, by the URL the real
    /// file will have.
    nonisolated private static func audioFiles(in root: URL) -> FolderWalk {
        var walk = FolderWalk()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else { return walk }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: Set(keys))

            if name.hasPrefix(".") {
                if values?.isDirectory == true {
                    enumerator.skipDescendants()
                } else if name.hasSuffix(".icloud") {
                    // ".Song.mp3.icloud" stands in for "Song.mp3".
                    let realName = String(name.dropFirst().dropLast(".icloud".count))
                    let real = url.deletingLastPathComponent().appendingPathComponent(realName)
                    if audioExtensions.contains(real.pathExtension.lowercased()) {
                        try? FileManager.default.startDownloadingUbiquitousItem(at: real)
                        walk.placeholders.append(real)
                    }
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }
            if audioExtensions.contains(url.pathExtension.lowercased()) {
                walk.files.append(url)
            }
        }
        return walk
    }

    /// Reads one file's tags. Falls back to the file name for anything the
    /// tags don't say, so an untagged rip still lists.
    nonisolated private static func readTrack(at url: URL, root: URL, artworkDirectory: URL) async -> FileTrack? {
        var track = FileTrack(
            relativePath: relativePath(of: url, in: root),
            title: url.deletingPathExtension().lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            isDownloaded: true
        )

        let asset = AVURLAsset(url: url)
        var artworkData: Data?

        if let common = try? await asset.load(.commonMetadata) {
            for item in common {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try? await item.load(.stringValue), !value.isEmpty { track.title = value }
                case .commonKeyArtist:
                    track.artist = try? await item.load(.stringValue)
                case .commonKeyAlbumName:
                    track.album = try? await item.load(.stringValue)
                case .commonKeyArtwork:
                    if artworkData == nil { artworkData = try? await item.load(.dataValue) }
                default:
                    break
                }
            }
        }

        if let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 {
            track.duration = duration.seconds
        }

        // Track number and album artist have no common key.
        if let all = try? await asset.load(.metadata) {
            let numberIdentifiers: [AVMetadataIdentifier] = [.id3MetadataTrackNumber, .iTunesMetadataTrackNumber]
            for identifier in numberIdentifiers where track.trackNumber == nil {
                for item in AVMetadataItem.metadataItems(from: all, filteredByIdentifier: identifier) {
                    if let value = try? await item.load(.value), let number = trackNumber(from: value) {
                        track.trackNumber = number
                        break
                    }
                }
            }
            let bandIdentifiers: [AVMetadataIdentifier] = [.id3MetadataBand, .iTunesMetadataAlbumArtist]
            for identifier in bandIdentifiers where track.albumArtist == nil {
                for item in AVMetadataItem.metadataItems(from: all, filteredByIdentifier: identifier) {
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        track.albumArtist = value
                        break
                    }
                }
            }
        }

        // One cover per album, written the first time it's seen.
        if let artworkData, !artworkData.isEmpty {
            let fileName = hash("\(track.groupingArtist)|\(track.albumTitle)") + ".img"
            let file = artworkDirectory.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: file.path) {
                try? artworkData.write(to: file)
            }
            track.artworkFileName = fileName
        }

        return track
    }

    /// ID3 carries "3/12" as a string; iTunes packs the number into bytes 2–3
    /// of an 8-byte blob.
    nonisolated private static func trackNumber(from value: any NSCopying & NSObjectProtocol) -> Int? {
        if let string = value as? String {
            return Int(string.split(separator: "/").first ?? "")
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let data = value as? Data, data.count >= 4 {
            let bytes = [UInt8](data)
            let number = Int(bytes[2]) << 8 | Int(bytes[3])
            return number > 0 ? number : nil
        }
        return nil
    }

    nonisolated private static func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    nonisolated private static func hash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Index

    /// Builds the songs, albums and artists from the tracks, with the URLs
    /// the current folder gives them.
    private func rebuildIndex() {
        var songs: [PlayableContent] = []
        var albumsByID: [String: PlayableContent] = [:]
        var artistsByID: [String: PlayableContent] = [:]
        var songIDsByAlbum: [String: [String]] = [:]
        var albumIDsByArtist: [String: [String]] = [:]
        var songsByID: [String: PlayableContent] = [:]

        for track in tracks {
            let artistName = track.groupingArtist
            let artistID = Self.hash("artist|\(artistName.lowercased())")
            let albumID = Self.hash("album|\(artistName.lowercased())|\(track.albumTitle.lowercased())")
            let songID = Self.hash("song|\(track.relativePath)")
            let url = folderURL?.appendingPathComponent(track.relativePath)
            let artwork = track.artworkFileName.map { Self.artworkDirectory.appendingPathComponent($0) }

            let song = PlayableContent(
                title: track.title,
                subtitle: [track.artist ?? "", track.fileExtension.uppercased()]
                    .filter { !$0.isEmpty }
                    .joined(separator: " • "),
                thumbnail: artwork,
                artwork: artwork,
                content: .init(service: .files, id: songID, type: .track, location: url),
                // The file itself: the on-device player reads it, and the
                // row's preview plays it in full like Plex and Subsonic.
                previewURL: track.isDownloaded ? url : nil,
                metadata: .init(
                    duration: track.duration.map { Duration.seconds($0) },
                    artist: track.artist ?? artistName,
                    artistID: artistID,
                    album: track.albumTitle,
                    albumID: albumID,
                    position: track.trackNumber,
                    audioCodec: track.fileExtension,
                    isPlayable: track.isDownloaded
                )
            )
            songs.append(song)
            songsByID[songID] = song
            songIDsByAlbum[albumID, default: []].append(songID)

            if albumsByID[albumID] == nil {
                albumsByID[albumID] = PlayableContent(
                    title: track.albumTitle,
                    subtitle: artistName,
                    thumbnail: artwork,
                    artwork: artwork,
                    content: .init(service: .files, id: albumID, type: .album, location: nil),
                    metadata: .init(artist: artistName, artistID: artistID, album: track.albumTitle, albumID: albumID)
                )
                albumIDsByArtist[artistID, default: []].append(albumID)
            } else if albumsByID[albumID]?.artwork == nil, artwork != nil {
                // The first file of an album may be untagged; take the cover
                // from whichever file has one.
                let existing = albumsByID[albumID]!
                albumsByID[albumID] = PlayableContent(
                    title: existing.title,
                    subtitle: existing.subtitle,
                    thumbnail: artwork,
                    artwork: artwork,
                    content: existing.content,
                    metadata: existing.metadata
                )
            }

            if artistsByID[artistID] == nil {
                artistsByID[artistID] = PlayableContent(
                    title: artistName,
                    subtitle: "",
                    thumbnail: artwork,
                    artwork: artwork,
                    content: .init(service: .files, id: artistID, type: .artist, location: nil),
                    metadata: .init(artist: artistName, artistID: artistID)
                )
            }
        }

        self.songsByID = songsByID
        self.albumsByID = albumsByID
        self.artistsByID = artistsByID
        self.songIDsByAlbum = songIDsByAlbum
        self.albumIDsByArtist = albumIDsByArtist
        self.songs = songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        self.albums = albumsByID.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        self.artists = artistsByID.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    // MARK: - Lookups

    public func track(id: String) -> PlayableContent? { songsByID[id] }
    public func album(id: String) -> PlayableContent? { albumsByID[id] }
    public func artist(id: String) -> PlayableContent? { artistsByID[id] }

    /// An album's songs in play order: disc and track number where the tags
    /// have them, file name otherwise.
    public func albumTracks(albumID: String) -> [PlayableContent] {
        let tracks = (songIDsByAlbum[albumID] ?? []).compactMap { songsByID[$0] }
        return tracks.sorted { lhs, rhs in
            switch (lhs.metadata?.position, rhs.metadata?.position) {
            case let (l?, r?) where l != r: return l < r
            case (nil, .some): return false
            case (.some, nil): return true
            default: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }

    public func artistAlbums(artistID: String) -> [PlayableContent] {
        (albumIDsByArtist[artistID] ?? []).compactMap { albumsByID[$0] }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Every song by an artist, album by album.
    public func artistTracks(artistID: String) -> [PlayableContent] {
        artistAlbums(artistID: artistID).flatMap { albumTracks(albumID: $0.content.id) }
    }

    /// A page of songs, for the paged lists.
    public func songs(offset: Int, limit: Int = 200) -> [PlayableContent] {
        Array(songs.dropFirst(max(0, offset)).prefix(limit))
    }

    public func search(query: String) -> [PlayableContent] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        func matches(_ content: PlayableContent) -> Bool {
            content.title.localizedStandardContains(query)
                || content.subtitle.localizedStandardContains(query)
                || (content.metadata?.album?.localizedStandardContains(query) ?? false)
        }
        return artists.filter(matches) + albums.filter(matches) + songs.filter(matches)
    }

    // MARK: - Storage

    private static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("FilesLibrary", isDirectory: true)
    }

    private static var indexURL: URL {
        supportDirectory.appendingPathComponent("index.json")
    }

    private static var artworkDirectory: URL {
        supportDirectory.appendingPathComponent("Artwork", isDirectory: true)
    }

    private static func loadIndex() -> [FileTrack] {
        guard let data = try? Data(contentsOf: indexURL),
              let tracks = try? JSONDecoder().decode([FileTrack].self, from: data) else { return [] }
        return tracks
    }

    private static func saveIndex(_ tracks: [FileTrack]) {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
