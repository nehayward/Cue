import AVFoundation
import CryptoKit
import Defaults
import Foundation
import Observation
import SwiftUI

/// One audio file in the picked folder, as read from its tags — or, where
/// the tags are silent, from where it sits and what it is called. Kept on
/// disk between launches so the library is there before a rescan.
struct FileTrack: Codable, Sendable, Hashable {
    /// Path under the picked folder — the stable identity of the file, since
    /// the folder's own URL can change between launches.
    var relativePath: String
    var title: String
    var artist: String?
    var albumArtist: String?
    var album: String?
    var genre: String?
    var year: Int?
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
    /// When the file last changed and how big it is: a rescan re-reads tags
    /// only when one of these moved, so a big library rescans in seconds.
    var modificationDate: Date?
    var fileSize: Int?

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

/// An `.m3u` playlist found in the folder, as the files it names that the
/// scan also found.
struct FilePlaylist: Codable, Sendable, Hashable {
    var relativePath: String
    var title: String
    var trackRelativePaths: [String]
}

/// The Files provider: audio files in one folder the user picked, on this
/// device or in iCloud Drive. The folder is held as a security-scoped
/// bookmark, walked for audio files, and each file's tags are read with
/// AVFoundation into songs, albums, artists and playlists. Nothing leaves
/// the device — there is no account and no server — so its tracks play on
/// this device only (`MusicService.playsOnDeviceOnly`), off their file URLs.
///
/// Untagged files fall back to the folder layout most ripped libraries use,
/// `Artist/Album/01 Title.mp3` (with an optional `Disc 1` level), so they
/// still land under the right artist and album.
///
/// iCloud Drive folders can hold files that aren't downloaded yet. Those
/// appear as hidden `.name.ext.icloud` placeholders; a scan asks the system
/// to download them and lists them by file name until the next scan can read
/// their tags.
@MainActor
@Observable
public final class FilesLibraryService {
    public static let shared = FilesLibraryService()

    /// The orders the Songs list offers. The index is in memory, so every
    /// order is a sort of the whole library, reversible for free.
    public enum SongSort: String, CaseIterable, Sendable {
        case title, artist, album, recentlyAdded, duration

        public var label: String {
            switch self {
            case .title: "Title"
            case .artist: "Artist"
            case .album: "Album"
            case .recentlyAdded: "Recently Added"
            case .duration: "Duration"
            }
        }

        public var ascendingLabel: String {
            switch self {
            case .title, .artist, .album: "A – Z"
            case .recentlyAdded: "Oldest First"
            case .duration: "Shortest First"
            }
        }

        public var descendingLabel: String {
            switch self {
            case .title, .artist, .album: "Z – A"
            case .recentlyAdded: "Newest First"
            case .duration: "Longest First"
            }
        }

        /// Whether the sort reads best descending — newest and longest
        /// first — so the list opens that way.
        public var prefersDescending: Bool {
            self == .recentlyAdded || self == .duration
        }
    }

    public enum AlbumSort: String, CaseIterable, Sendable {
        case title, artist, year, recentlyAdded

        public var label: String {
            switch self {
            case .title: "Title"
            case .artist: "Artist"
            case .year: "Year"
            case .recentlyAdded: "Recently Added"
            }
        }

        public var ascendingLabel: String {
            switch self {
            case .title, .artist: "A – Z"
            case .year, .recentlyAdded: "Oldest First"
            }
        }

        public var descendingLabel: String {
            switch self {
            case .title, .artist: "Z – A"
            case .year, .recentlyAdded: "Newest First"
            }
        }

        public var prefersDescending: Bool {
            self == .year || self == .recentlyAdded
        }
    }

    public private(set) var songs: [PlayableContent] = []
    public private(set) var albums: [PlayableContent] = []
    public private(set) var artists: [PlayableContent] = []
    public private(set) var playlists: [PlayableContent] = []

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

    /// A container standing for every song in the folder, for the Songs
    /// list's Play All: a playlist with a well-known id that the local queue
    /// expands into the whole library.
    nonisolated public static let allSongsID = "all-songs"

    public var allSongsContainer: PlayableContent {
        PlayableContent(
            title: "All Songs",
            subtitle: folderName ?? "Files",
            thumbnail: nil,
            artwork: nil,
            content: .init(service: .files, id: Self.allSongsID, type: .playlist, location: nil)
        )
    }

    @ObservationIgnored private var folderURL: URL?
    @ObservationIgnored private var isAccessingFolder = false
    @ObservationIgnored private var tracks: [FileTrack] = []
    @ObservationIgnored private var filePlaylists: [FilePlaylist] = []
    @ObservationIgnored private var tracksByID: [String: FileTrack] = [:]
    @ObservationIgnored private var songsByID: [String: PlayableContent] = [:]
    @ObservationIgnored private var albumsByID: [String: PlayableContent] = [:]
    @ObservationIgnored private var artistsByID: [String: PlayableContent] = [:]
    @ObservationIgnored private var playlistsByID: [String: PlayableContent] = [:]
    @ObservationIgnored private var songIDsByAlbum: [String: [String]] = [:]
    @ObservationIgnored private var albumIDsByArtist: [String: [String]] = [:]
    @ObservationIgnored private var songIDsByPlaylist: [String: [String]] = [:]
    @ObservationIgnored private var songIDByPath: [String: String] = [:]
    @ObservationIgnored private var albumAdded: [String: Date] = [:]
    @ObservationIgnored private var albumYear: [String: Int] = [:]
    @ObservationIgnored private var sortedSongs: [String: [PlayableContent]] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard

    nonisolated private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aif", "aiff", "aifc", "caf", "m4b", "alac"
    ]
    nonisolated private static let playlistExtensions: Set<String> = ["m3u", "m3u8"]

    /// A scan older than this is refreshed in the background the next time
    /// the library is opened — cheap, since unchanged files aren't re-read.
    private static let staleAfter: TimeInterval = 10 * 60

    private init() {
        folderName = defaults.string(forKey: AppStorageKeys.filesFolderName)
        resolveFolder()
        let stored = Self.loadIndex()
        tracks = stored.tracks
        filePlaylists = stored.playlists
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

        scanTask?.cancel()
        stopAccessingFolder()
        tracks = []
        filePlaylists = []
        lastScan = nil
        rebuildIndex()
        resolveFolder()
        rescan()
    }

    /// Forgets the folder and everything indexed from it.
    public func removeFolder() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        stopCloudMonitor()
        stopAccessingFolder()
        folderURL = nil
        folderName = nil
        lastError = nil
        lastScan = nil
        pendingDownloadCount = 0
        tracks = []
        filePlaylists = []
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
    /// screens and search call before reading. With an index already there,
    /// an old one is refreshed in the background instead, so new files show
    /// up without a manual rescan.
    public func scanIfNeeded() async {
        guard isConfigured, !isScanning else { return }
        if tracks.isEmpty {
            await scan()
            return
        }
        let isStale = lastScan.map { Date.now.timeIntervalSince($0) > Self.staleAfter } ?? true
        if isStale {
            rescan()
        }
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
            Self.walkFolder(root)
        }.value
        guard !Task.isCancelled else { return }
        foundCount = walk.files.count + walk.placeholders.count
        pendingDownloadCount = walk.placeholders.count

        // Only files that changed since the last scan have their tags read
        // again; the rest keep what they had.
        let previous = Dictionary(tracks.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        var kept: [FileTrack] = []
        var toRead: [FolderWalk.Entry] = []
        for entry in walk.files {
            let path = Self.relativePath(of: entry.url, in: root)
            if let old = previous[path], old.isDownloaded,
               old.modificationDate == entry.modificationDate, old.fileSize == entry.fileSize {
                kept.append(old)
            } else {
                toRead.append(entry)
            }
        }
        scannedCount = kept.count

        // Tags are read a few files at a time: AVFoundation opens each file,
        // and a folder can hold thousands.
        var read: [FileTrack] = []
        var next = 0
        await withTaskGroup(of: FileTrack?.self) { group in
            let width = min(4, toRead.count)
            while next < width {
                let entry = toRead[next]
                next += 1
                group.addTask { await Self.readTrack(entry, root: root, artworkDirectory: artworkDirectory) }
            }
            while let result = await group.next() {
                if let result { read.append(result) }
                scannedCount += 1
                if Task.isCancelled { group.cancelAll() }
                if next < toRead.count, !Task.isCancelled {
                    let entry = toRead[next]
                    next += 1
                    group.addTask { await Self.readTrack(entry, root: root, artworkDirectory: artworkDirectory) }
                }
            }
        }
        guard !Task.isCancelled else { return }

        // Placeholders are listed by name until they download.
        let placeholders = walk.placeholders.map { url -> FileTrack in
            var track = FileTrack(
                relativePath: Self.relativePath(of: url, in: root),
                title: url.deletingPathExtension().lastPathComponent,
                fileExtension: url.pathExtension.lowercased(),
                isDownloaded: false
            )
            Self.applyFolderLayout(to: &track, url: url, root: root, titleFromFileName: true)
            return track
        }

        let all = (kept + read + placeholders)
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        let known = Set(all.map(\.relativePath))
        let playlists = await Task.detached(priority: .userInitiated) {
            Self.readPlaylists(walk.playlists, root: root, knownPaths: known)
        }.value
        guard !Task.isCancelled else { return }

        tracks = all
        filePlaylists = playlists
        lastScan = .now
        rebuildIndex()
        Self.saveIndex(tracks: tracks, playlists: filePlaylists)
    }

    private struct FolderWalk: Sendable {
        struct Entry: Sendable {
            var url: URL
            var modificationDate: Date?
            var fileSize: Int?
        }
        var files: [Entry] = []
        var placeholders: [URL] = []
        var playlists: [URL] = []
    }

    /// Every audio file and playlist under `root`. iCloud placeholders
    /// (`.name.ext.icloud`) are asked to download and reported separately,
    /// by the URL the real file will have.
    nonisolated private static func walkFolder(_ root: URL) -> FolderWalk {
        var walk = FolderWalk()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
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
            let ext = url.pathExtension.lowercased()
            if audioExtensions.contains(ext) {
                walk.files.append(.init(url: url, modificationDate: values?.contentModificationDate, fileSize: values?.fileSize))
            } else if playlistExtensions.contains(ext) {
                walk.playlists.append(url)
            }
        }
        return walk
    }

    /// Reads one file's tags, then fills whatever they left out from the
    /// file's name and the folders above it, so an untagged rip still lists
    /// under its artist and album.
    nonisolated private static func readTrack(_ entry: FolderWalk.Entry, root: URL, artworkDirectory: URL) async -> FileTrack? {
        let url = entry.url
        var track = FileTrack(
            relativePath: relativePath(of: url, in: root),
            title: url.deletingPathExtension().lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            isDownloaded: true,
            modificationDate: entry.modificationDate,
            fileSize: entry.fileSize
        )
        var titleFromFileName = true

        let asset = AVURLAsset(url: url)
        var artworkData: Data?

        if let common = try? await asset.load(.commonMetadata) {
            for item in common {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try? await item.load(.stringValue), !value.isEmpty {
                        track.title = value
                        titleFromFileName = false
                    }
                case .commonKeyArtist:
                    track.artist = nonEmpty(try? await item.load(.stringValue))
                case .commonKeyAlbumName:
                    track.album = nonEmpty(try? await item.load(.stringValue))
                case .commonKeyType:
                    track.genre = nonEmpty(try? await item.load(.stringValue))
                case .commonKeyCreationDate:
                    if let value = try? await item.load(.stringValue) { track.year = year(from: value) }
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

        // Track and disc numbers, album artist, genre and year have no
        // common key; ID3 and iTunes each spell them their own way.
        if let all = try? await asset.load(.metadata) {
            if track.trackNumber == nil {
                track.trackNumber = await number(in: all, [.id3MetadataTrackNumber, .iTunesMetadataTrackNumber])
            }
            if track.discNumber == nil {
                track.discNumber = await number(in: all, [.id3MetadataPartOfASet, .iTunesMetadataDiscNumber])
            }
            if track.albumArtist == nil {
                track.albumArtist = await string(in: all, [.id3MetadataBand, .iTunesMetadataAlbumArtist])
            }
            if track.genre == nil {
                track.genre = await string(in: all, [.id3MetadataContentType, .iTunesMetadataUserGenre])
            }
            if track.year == nil, let dated = await string(in: all, [.id3MetadataRecordingTime, .id3MetadataYear, .iTunesMetadataReleaseDate]) {
                track.year = year(from: dated)
            }
        }

        applyFolderLayout(to: &track, url: url, root: root, titleFromFileName: titleFromFileName)

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

    /// The layout fallback. Folders above the file stand in for missing
    /// tags — `Artist/Album/Song.mp3`, or `Artist/Album/Disc 2/Song.mp3` —
    /// and a leading number on the file name is the track number, with the
    /// rest as the title when the tags had none.
    nonisolated private static func applyFolderLayout(to track: inout FileTrack, url: URL, root: URL, titleFromFileName: Bool) {
        var folders: [String] = []
        var parent = url.deletingLastPathComponent()
        let rootPath = root.standardizedFileURL.path
        while parent.standardizedFileURL.path.hasPrefix(rootPath), parent.standardizedFileURL.path != rootPath, folders.count < 3 {
            folders.insert(parent.lastPathComponent, at: 0)
            parent = parent.deletingLastPathComponent()
        }

        // A "Disc 2" / "CD2" folder names the disc, not the album.
        if let last = folders.last, let disc = discNumber(fromFolder: last) {
            if track.discNumber == nil { track.discNumber = disc }
            folders.removeLast()
        }

        if track.album == nil, let albumFolder = folders.last {
            track.album = albumFolder
            if track.artist == nil, track.albumArtist == nil, folders.count >= 2 {
                track.artist = folders[folders.count - 2]
            }
        } else if track.artist == nil, track.albumArtist == nil, folders.count >= 2 {
            track.artist = folders[folders.count - 2]
        }

        // "03 Title", "03 - Title", "03. Title", "1-03 Title" (disc-track).
        let fileName = url.deletingPathExtension().lastPathComponent
        if let match = fileName.firstMatch(of: /^\s*(?:(\d)[-.])?(\d{1,3})\s*[-._)]?\s+(.+)$/) {
            if track.trackNumber == nil { track.trackNumber = Int(match.2) }
            if track.discNumber == nil, let disc = match.1 { track.discNumber = Int(disc) }
            if titleFromFileName {
                let rest = String(match.3).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { track.title = rest }
            }
        }
    }

    nonisolated private static func discNumber(fromFolder name: String) -> Int? {
        guard let match = name.firstMatch(of: /^(?:disc|disk|cd)\s*(\d{1,2})$/.ignoresCase()) else { return nil }
        return Int(match.1)
    }

    nonisolated private static func number(in metadata: [AVMetadataItem], _ identifiers: [AVMetadataIdentifier]) async -> Int? {
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier) {
                if let value = try? await item.load(.value), let number = packedNumber(from: value) {
                    return number
                }
            }
        }
        return nil
    }

    nonisolated private static func string(in metadata: [AVMetadataItem], _ identifiers: [AVMetadataIdentifier]) async -> String? {
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier) {
                if let value = nonEmpty(try? await item.load(.stringValue)) {
                    return value
                }
            }
        }
        return nil
    }

    /// ID3 carries "3/12" as a string; iTunes packs the number into bytes 2–3
    /// of an 8-byte blob.
    nonisolated private static func packedNumber(from value: any NSCopying & NSObjectProtocol) -> Int? {
        if let string = value as? String {
            return Int(string.split(separator: "/").first?.trimmingCharacters(in: .whitespaces) ?? "")
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

    /// The first four-digit year in a date string, whatever else it holds.
    nonisolated private static func year(from string: String) -> Int? {
        guard let match = string.firstMatch(of: /(?<!\d)(\d{4})(?!\d)/) else { return nil }
        let value = Int(match.1) ?? 0
        return (1900...2100).contains(value) ? value : nil
    }

    nonisolated private static func nonEmpty(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Reads each `.m3u` as the tracks it names, resolved against the
    /// playlist's own folder (or the root for absolute paths) and kept only
    /// where the scan found the file.
    nonisolated private static func readPlaylists(_ urls: [URL], root: URL, knownPaths: Set<String>) -> [FilePlaylist] {
        let rootPath = root.standardizedFileURL.path
        return urls.compactMap { url -> FilePlaylist? in
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
            let directory = url.deletingLastPathComponent()
            var paths: [String] = []
            var title = url.deletingPathExtension().lastPathComponent
            for rawLine in text.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: "/")
                guard !line.isEmpty else { continue }
                if line.hasPrefix("#") {
                    // A rename keeps the file name and writes the new name
                    // here, so the playlist's id (its path) holds still.
                    if line.hasPrefix("#PLAYLIST:") {
                        let named = line.dropFirst("#PLAYLIST:".count).trimmingCharacters(in: .whitespaces)
                        if !named.isEmpty { title = named }
                    }
                    continue
                }
                let resolved: URL
                if line.hasPrefix("file://"), let fileURL = URL(string: line) {
                    resolved = fileURL
                } else if line.hasPrefix("/") {
                    resolved = URL(fileURLWithPath: line)
                } else {
                    resolved = directory.appendingPathComponent(line)
                }
                let path = resolved.standardizedFileURL.path
                let relative: String
                if path.hasPrefix(rootPath) {
                    relative = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                } else {
                    // An absolute path from another machine: match on the
                    // tail, which is how most exported playlists still line up.
                    guard let hit = knownPaths.first(where: { path.hasSuffix("/" + $0) }) else { continue }
                    relative = hit
                }
                if knownPaths.contains(relative), !paths.contains(relative) {
                    paths.append(relative)
                }
            }
            // An empty playlist is still a playlist — one Cue just created,
            // waiting for its first song.
            return FilePlaylist(
                relativePath: relativePath(of: url, in: root),
                title: title,
                trackRelativePaths: paths
            )
        }
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

    /// Builds the songs, albums, artists and playlists from the tracks, with
    /// the URLs the current folder gives them.
    private func rebuildIndex() {
        var songs: [PlayableContent] = []
        var tracksByID: [String: FileTrack] = [:]
        var albumsByID: [String: PlayableContent] = [:]
        var artistsByID: [String: PlayableContent] = [:]
        var songIDsByAlbum: [String: [String]] = [:]
        var albumIDsByArtist: [String: [String]] = [:]
        var songsByID: [String: PlayableContent] = [:]
        var songIDByPath: [String: String] = [:]
        var albumAdded: [String: Date] = [:]
        var albumYear: [String: Int] = [:]
        var albumArtwork: [String: URL] = [:]

        // Pass one: what each album is called, dated and pictured.
        for track in tracks {
            let artistName = track.groupingArtist
            let albumID = Self.hash("album|\(artistName.lowercased())|\(track.albumTitle.lowercased())")
            if let added = track.modificationDate, (albumAdded[albumID] ?? .distantPast) < added {
                albumAdded[albumID] = added
            }
            if let year = track.year, (albumYear[albumID] ?? 0) < year {
                albumYear[albumID] = year
            }
            if albumArtwork[albumID] == nil, let name = track.artworkFileName {
                albumArtwork[albumID] = Self.artworkDirectory.appendingPathComponent(name)
            }
        }

        for track in tracks {
            let artistName = track.groupingArtist
            let artistID = Self.hash("artist|\(artistName.lowercased())")
            let albumID = Self.hash("album|\(artistName.lowercased())|\(track.albumTitle.lowercased())")
            let songID = Self.hash("song|\(track.relativePath)")
            let url = folderURL?.appendingPathComponent(track.relativePath)
            let artwork = track.artworkFileName.map { Self.artworkDirectory.appendingPathComponent($0) } ?? albumArtwork[albumID]
            let year = albumYear[albumID]

            let song = PlayableContent(
                title: track.title,
                subtitle: [track.artist ?? artistName, track.fileExtension.uppercased()]
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
                    albumYear: year.flatMap { Self.date(year: $0) },
                    position: track.trackNumber,
                    audioCodec: track.fileExtension,
                    isPlayable: track.isDownloaded
                )
            )
            songs.append(song)
            songsByID[songID] = song
            tracksByID[songID] = track
            songIDByPath[track.relativePath] = songID
            songIDsByAlbum[albumID, default: []].append(songID)

            if albumsByID[albumID] == nil {
                albumsByID[albumID] = PlayableContent(
                    title: track.albumTitle,
                    subtitle: [artistName, year.map(String.init) ?? ""]
                        .filter { !$0.isEmpty }
                        .joined(separator: " • "),
                    thumbnail: artwork,
                    artwork: artwork,
                    content: .init(service: .files, id: albumID, type: .album, location: nil),
                    metadata: .init(
                        artist: artistName,
                        artistID: artistID,
                        album: track.albumTitle,
                        albumID: albumID,
                        albumYear: year.flatMap { Self.date(year: $0) }
                    )
                )
                albumIDsByArtist[artistID, default: []].append(albumID)
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

        var playlistsByID: [String: PlayableContent] = [:]
        var songIDsByPlaylist: [String: [String]] = [:]
        for playlist in filePlaylists {
            let id = Self.hash("playlist|\(playlist.relativePath)")
            let ids = playlist.trackRelativePaths.compactMap { songIDByPath[$0] }
            let first = ids.first.flatMap { songsByID[$0] }
            playlistsByID[id] = PlayableContent(
                title: playlist.title,
                subtitle: ids.isEmpty ? "Empty" : (ids.count == 1 ? "1 song" : "\(ids.count) songs"),
                thumbnail: first?.thumbnail,
                artwork: first?.artwork,
                content: .init(service: .files, id: id, type: .playlist, location: folderURL?.appendingPathComponent(playlist.relativePath))
            )
            songIDsByPlaylist[id] = ids
        }

        self.tracksByID = tracksByID
        self.songsByID = songsByID
        self.albumsByID = albumsByID
        self.artistsByID = artistsByID
        self.playlistsByID = playlistsByID
        self.songIDsByAlbum = songIDsByAlbum
        self.albumIDsByArtist = albumIDsByArtist
        self.songIDsByPlaylist = songIDsByPlaylist
        self.songIDByPath = songIDByPath
        self.albumAdded = albumAdded
        self.albumYear = albumYear
        self.sortedSongs = [:]
        self.songs = songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        self.albums = albumsByID.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        self.artists = artistsByID.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        self.playlists = playlistsByID.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func date(year: Int) -> Date? {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 1, day: 1))
    }

    // MARK: - Lookups

    public func track(id: String) -> PlayableContent? { songsByID[id] }
    public func album(id: String) -> PlayableContent? { albumsByID[id] }
    public func artist(id: String) -> PlayableContent? { artistsByID[id] }

    public func playlist(id: String) -> PlayableContent? {
        id == Self.allSongsID ? allSongsContainer : playlistsByID[id]
    }

    /// An album's songs in play order: disc and track number where the tags
    /// or file names have them, title otherwise.
    public func albumTracks(albumID: String) -> [PlayableContent] {
        let ids = songIDsByAlbum[albumID] ?? []
        return ids.compactMap { songsByID[$0] }.sorted { lhs, rhs in
            let l = tracksByID[lhs.content.id]
            let r = tracksByID[rhs.content.id]
            let lDisc = l?.discNumber ?? 1
            let rDisc = r?.discNumber ?? 1
            if lDisc != rDisc { return lDisc < rDisc }
            switch (l?.trackNumber, r?.trackNumber) {
            case let (a?, b?) where a != b: return a < b
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

    /// A playlist's songs in the order the file lists them; the All Songs
    /// container is the whole library by title.
    public func playlistTracks(playlistID: String) -> [PlayableContent] {
        if playlistID == Self.allSongsID { return songs }
        return (songIDsByPlaylist[playlistID] ?? []).compactMap { songsByID[$0] }
    }

    /// A page of songs in one of the offered orders. Each order is sorted
    /// once and kept until the index changes, so paging is a slice.
    public func songs(sortedBy sort: SongSort = .title, descending: Bool = false, offset: Int, limit: Int = 200) -> [PlayableContent] {
        let key = "\(sort.rawValue).\(descending)"
        let ordered: [PlayableContent]
        if let cached = sortedSongs[key] {
            ordered = cached
        } else {
            ordered = sortSongs(songs, by: sort, descending: descending)
            sortedSongs[key] = ordered
        }
        return Array(ordered.dropFirst(max(0, offset)).prefix(limit))
    }

    private func sortSongs(_ songs: [PlayableContent], by sort: SongSort, descending: Bool) -> [PlayableContent] {
        func track(_ song: PlayableContent) -> FileTrack? { tracksByID[song.content.id] }
        let ascending: (PlayableContent, PlayableContent) -> Bool
        switch sort {
        case .title:
            ascending = { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            ascending = { lhs, rhs in
                let l = lhs.metadata?.artist ?? ""
                let r = rhs.metadata?.artist ?? ""
                if l != r { return l.localizedStandardCompare(r) == .orderedAscending }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        case .album:
            ascending = { lhs, rhs in
                let l = lhs.metadata?.album ?? ""
                let r = rhs.metadata?.album ?? ""
                if l != r { return l.localizedStandardCompare(r) == .orderedAscending }
                return (lhs.metadata?.position ?? 0) < (rhs.metadata?.position ?? 0)
            }
        case .recentlyAdded:
            ascending = { (track($0)?.modificationDate ?? .distantPast) < (track($1)?.modificationDate ?? .distantPast) }
        case .duration:
            ascending = { (track($0)?.duration ?? 0) < (track($1)?.duration ?? 0) }
        }
        return descending ? songs.sorted { ascending($1, $0) } : songs.sorted(by: ascending)
    }

    public func albums(sortedBy sort: AlbumSort = .title, descending: Bool = false) -> [PlayableContent] {
        let ascending: (PlayableContent, PlayableContent) -> Bool
        switch sort {
        case .title:
            ascending = { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .artist:
            ascending = { lhs, rhs in
                let l = lhs.metadata?.artist ?? ""
                let r = rhs.metadata?.artist ?? ""
                if l != r { return l.localizedStandardCompare(r) == .orderedAscending }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        case .year:
            ascending = { [albumYear] lhs, rhs in
                let l = albumYear[lhs.content.id] ?? 0
                let r = albumYear[rhs.content.id] ?? 0
                if l != r { return l < r }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        case .recentlyAdded:
            ascending = { [albumAdded] lhs, rhs in
                (albumAdded[lhs.content.id] ?? .distantPast) < (albumAdded[rhs.content.id] ?? .distantPast)
            }
        }
        return descending ? albums.sorted { ascending($1, $0) } : albums.sorted(by: ascending)
    }

    /// The newest albums by when their files arrived in the folder.
    public func recentlyAddedAlbums(limit: Int = 100) -> [PlayableContent] {
        Array(albums(sortedBy: .recentlyAdded, descending: true).prefix(limit))
    }

    public func search(query: String) -> [PlayableContent] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        func matches(_ content: PlayableContent) -> Bool {
            content.title.localizedStandardContains(query)
                || content.subtitle.localizedStandardContains(query)
                || (content.metadata?.album?.localizedStandardContains(query) ?? false)
        }
        return artists.filter(matches) + albums.filter(matches) + playlists.filter(matches) + songs.filter(matches)
    }

    // MARK: - Playlist editing

    /// Playlists Cue creates live in a `Playlists` folder inside the picked
    /// folder, as plain `.m3u` files any other player can read. Playlists
    /// found elsewhere in the folder are edited where they are.
    private var playlistsDirectory: URL? {
        folderURL?.appendingPathComponent("Playlists", isDirectory: true)
    }

    private func playlistIndex(id: String) -> Int? {
        filePlaylists.firstIndex { Self.hash("playlist|\($0.relativePath)") == id }
    }

    /// Creates a playlist, seeded with `track` when one is given. The name
    /// becomes the file name (a duplicate gets a number, as Finder does).
    public func createPlaylist(name: String, seededWith track: PlayableContent? = nil) async -> PlayableContent? {
        guard let folderURL, let playlistsDirectory else { return nil }
        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeName.isEmpty else { return nil }

        var url = playlistsDirectory.appendingPathComponent(safeName).appendingPathExtension("m3u")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = playlistsDirectory.appendingPathComponent("\(safeName) \(counter)").appendingPathExtension("m3u")
            counter += 1
        }

        let paths = [track].compactMap { $0 }.compactMap { tracksByID[$0.content.id]?.relativePath }
        let playlist = FilePlaylist(
            relativePath: Self.relativePath(of: url, in: folderURL),
            title: safeName,
            trackRelativePaths: paths
        )
        guard await write(playlist) else { return nil }
        filePlaylists.append(playlist)
        commitPlaylists()
        return self.playlist(id: Self.hash("playlist|\(playlist.relativePath)"))
    }

    /// Renames in place: the new name is written into the file as a
    /// `#PLAYLIST:` line and the file name stays, so the playlist's id — its
    /// path — and everything holding it stay valid.
    public func renamePlaylist(id: String, to name: String) async -> PlayableContent? {
        guard let index = playlistIndex(id: id) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var playlist = filePlaylists[index]
        playlist.title = trimmed
        guard await write(playlist) else { return nil }
        filePlaylists[index] = playlist
        commitPlaylists()
        return self.playlist(id: id)
    }

    public func deletePlaylist(id: String) async -> Bool {
        guard let folderURL, let index = playlistIndex(id: id) else { return false }
        let url = folderURL.appendingPathComponent(filePlaylists[index].relativePath)
        guard await Task.detached(priority: .userInitiated, operation: { Self.coordinatedDelete(url) }).value else { return false }
        filePlaylists.remove(at: index)
        commitPlaylists()
        return true
    }

    public func addToPlaylist(trackID: String, playlistID: String) async -> Bool {
        guard let index = playlistIndex(id: playlistID), let track = tracksByID[trackID] else { return false }
        var playlist = filePlaylists[index]
        playlist.trackRelativePaths.append(track.relativePath)
        guard await write(playlist) else { return false }
        filePlaylists[index] = playlist
        commitPlaylists()
        return true
    }

    /// Removes one occurrence: the one at `position` when it is that track,
    /// otherwise the first.
    public func removeFromPlaylist(trackID: String, playlistID: String, position: Int? = nil) async -> Bool {
        guard let index = playlistIndex(id: playlistID), let track = tracksByID[trackID] else { return false }
        var playlist = filePlaylists[index]
        let at: Int?
        if let position, playlist.trackRelativePaths.indices.contains(position),
           playlist.trackRelativePaths[position] == track.relativePath {
            at = position
        } else {
            at = playlist.trackRelativePaths.firstIndex(of: track.relativePath)
        }
        guard let at else { return false }
        playlist.trackRelativePaths.remove(at: at)
        guard await write(playlist) else { return false }
        filePlaylists[index] = playlist
        commitPlaylists()
        return true
    }

    /// `from` and `to` are SwiftUI's move offsets.
    public func reorderPlaylist(id: String, from: Int, to: Int) async -> Bool {
        guard let index = playlistIndex(id: id) else { return false }
        var playlist = filePlaylists[index]
        guard playlist.trackRelativePaths.indices.contains(from), (0...playlist.trackRelativePaths.count).contains(to) else { return false }
        playlist.trackRelativePaths.move(fromOffsets: IndexSet(integer: from), toOffset: to)
        guard await write(playlist) else { return false }
        filePlaylists[index] = playlist
        commitPlaylists()
        return true
    }

    private func commitPlaylists() {
        rebuildIndex()
        Self.saveIndex(tracks: tracks, playlists: filePlaylists)
    }

    /// Writes a playlist as Extended M3U — a `#PLAYLIST:` name, an `#EXTINF`
    /// line per song, and paths relative to the file — coordinated so an
    /// iCloud Drive folder sees one clean replacement.
    private func write(_ playlist: FilePlaylist) async -> Bool {
        guard let folderURL else { return false }
        let url = folderURL.appendingPathComponent(playlist.relativePath)
        let directory = (playlist.relativePath as NSString).deletingLastPathComponent
        var lines = ["#EXTM3U", "#PLAYLIST:\(playlist.title)"]
        for path in playlist.trackRelativePaths {
            if let id = songIDByPath[path], let track = tracksByID[id] {
                let seconds = Int((track.duration ?? -1).rounded())
                lines.append("#EXTINF:\(seconds),\(track.artist ?? track.groupingArtist) - \(track.title)")
            }
            lines.append(Self.relativePath(from: directory, to: path))
        }
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        return await Task.detached(priority: .userInitiated) { Self.coordinatedWrite(data, to: url) }.value
    }

    nonisolated private static func coordinatedWrite(_ data: Data, to url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?
        var succeeded = false
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            succeeded = (try? data.write(to: target, options: .atomic)) != nil
        }
        return succeeded && coordinationError == nil
    }

    nonisolated private static func coordinatedDelete(_ url: URL) -> Bool {
        var coordinationError: NSError?
        var succeeded = false
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
            succeeded = (try? FileManager.default.removeItem(at: target)) != nil
        }
        return succeeded && coordinationError == nil
    }

    /// The path from one folder to a file, both given relative to the root:
    /// "../Artist/Album/01 Song.mp3" from a playlist in "Playlists".
    nonisolated private static func relativePath(from directory: String, to path: String) -> String {
        let from = directory.split(separator: "/").map(String.init)
        let to = path.split(separator: "/").map(String.init)
        var common = 0
        while common < from.count, common < to.count, from[common] == to[common] {
            common += 1
        }
        let ups = Array(repeating: "..", count: from.count - common)
        return (ups + to[common...]).joined(separator: "/")
    }

    // MARK: - iCloud Drive

    /// Where a file in an iCloud Drive folder is.
    public enum CloudStatus: Equatable, Sendable {
        /// On this device.
        case local
        /// Coming down, with the fraction done where the system reports one.
        case downloading(Double?)
        /// Only in iCloud; playing it means fetching it first.
        case notDownloaded
        /// The folder isn't in iCloud Drive at all.
        case notCloud
    }

    /// Download progress by relative path for files on their way down, kept
    /// fresh while something is watching (`startCloudMonitor`).
    public private(set) var cloudProgress: [String: Double] = [:]

    @ObservationIgnored private var cloudQuery: NSMetadataQuery?
    @ObservationIgnored private var cloudObservers: [NSObjectProtocol] = []

    public func cloudStatus(trackID: String) -> CloudStatus {
        guard isCloudFolder, let track = tracksByID[trackID], let folderURL else { return .notCloud }
        if let progress = cloudProgress[track.relativePath] { return .downloading(progress) }
        let url = folderURL.appendingPathComponent(track.relativePath)
        guard FileManager.default.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey])
        else { return .notDownloaded }
        if values.ubiquitousItemIsDownloading == true { return .downloading(nil) }
        return values.ubiquitousItemDownloadingStatus == .current ? .local : .notDownloaded
    }

    /// The song a relative path stands for, for the rows that report
    /// progress by path.
    public func song(atRelativePath path: String) -> PlayableContent? {
        songIDByPath[path].flatMap { songsByID[$0] }
    }

    /// How much of the folder is on this device. Touches every file, so
    /// it's for the Downloads screen rather than a row.
    public func cloudSummary() -> (local: Int, remote: Int) {
        guard isCloudFolder else { return (tracks.count, 0) }
        var local = 0
        var remote = 0
        for track in tracks {
            switch cloudStatus(trackID: Self.hash("song|\(track.relativePath)")) {
            case .local: local += 1
            default: remote += 1
            }
        }
        return (local, remote)
    }

    /// Asks iCloud for the files. The system carries the transfer itself,
    /// app suspended or not, and the scan notices when they land.
    public func downloadFromCloud(trackIDs: [String]) {
        guard let folderURL else { return }
        for id in trackIDs {
            guard let track = tracksByID[id] else { continue }
            try? FileManager.default.startDownloadingUbiquitousItem(at: folderURL.appendingPathComponent(track.relativePath))
        }
        startCloudMonitor()
    }

    /// Every song not on this device.
    public func downloadAllFromCloud() {
        let ids = tracks.compactMap { track -> String? in
            let id = Self.hash("song|\(track.relativePath)")
            return cloudStatus(trackID: id) == .notDownloaded ? id : nil
        }
        downloadFromCloud(trackIDs: ids)
    }

    /// Hands the space back; the files stay in iCloud and list as before.
    public func removeFromDevice(trackIDs: [String]) {
        guard let folderURL else { return }
        for id in trackIDs {
            guard let track = tracksByID[id] else { continue }
            try? FileManager.default.evictUbiquitousItem(at: folderURL.appendingPathComponent(track.relativePath))
        }
    }

    public func removeAllFromDevice() {
        removeFromDevice(trackIDs: tracks.map { Self.hash("song|\($0.relativePath)") })
    }

    /// Watches the folder's downloads for live progress. Cheap while it
    /// runs and stopped when the screen goes; a placeholder that finishes
    /// while it watches triggers the incremental rescan that reads its tags.
    public func startCloudMonitor() {
        #if os(iOS) || os(macOS) || targetEnvironment(macCatalyst)
        guard cloudQuery == nil, isCloudFolder, let folderURL else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope, NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, folderURL.standardizedFileURL.path)
        query.notificationBatchingInterval = 0.5
        let names: [Notification.Name] = [.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate]
        cloudObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.readCloudQuery() }
            }
        }
        cloudQuery = query
        query.start()
        #endif
    }

    public func stopCloudMonitor() {
        cloudQuery?.stop()
        cloudQuery = nil
        cloudObservers.forEach { NotificationCenter.default.removeObserver($0) }
        cloudObservers = []
        cloudProgress = [:]
    }

    private func readCloudQuery() {
        #if os(iOS) || os(macOS) || targetEnvironment(macCatalyst)
        guard let query = cloudQuery, let folderURL else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        let rootPath = folderURL.standardizedFileURL.path
        var progress: [String: Double] = [:]
        var landed = false
        for case let item as NSMetadataItem in query.results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String, path.hasPrefix(rootPath) else { continue }
            let relative = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                if let id = songIDByPath[relative], tracksByID[id]?.isDownloaded == false { landed = true }
                continue
            }
            let isDownloading = (item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool) ?? false
            guard isDownloading else { continue }
            let percent = (item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double) ?? 0
            progress[relative] = percent / 100
        }
        cloudProgress = progress
        if landed, !isScanning {
            rescan()
        }
        #endif
    }

    // MARK: - Storage

    private struct StoredIndex: Codable {
        var tracks: [FileTrack]
        var playlists: [FilePlaylist]
    }

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

    private static func loadIndex() -> (tracks: [FileTrack], playlists: [FilePlaylist]) {
        guard let data = try? Data(contentsOf: indexURL) else { return ([], []) }
        if let stored = try? JSONDecoder().decode(StoredIndex.self, from: data) {
            return (stored.tracks, stored.playlists)
        }
        // The first build stored the bare track list.
        if let tracks = try? JSONDecoder().decode([FileTrack].self, from: data) {
            return (tracks, [])
        }
        return ([], [])
    }

    private static func saveIndex(tracks: [FileTrack], playlists: [FilePlaylist]) {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(StoredIndex(tracks: tracks, playlists: playlists)) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
