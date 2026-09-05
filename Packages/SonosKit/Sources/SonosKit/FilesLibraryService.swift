import AVFoundation
import CryptoKit
import Defaults
import Foundation
import Observation
import OSLog
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
    /// Whether the file's own tags have been read — for a song still in
    /// iCloud, by reading just its header. Nil in an index from before this
    /// existed, when only downloaded files had been read.
    var tagsRead: Bool?

    var hasReadTags: Bool { tagsRead ?? isDownloaded }

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

    public var songs: [PlayableContent] { catalog.songs }
    public var albums: [PlayableContent] { catalog.albums }
    public var artists: [PlayableContent] { catalog.artists }
    public var playlists: [PlayableContent] { catalog.playlists }
    /// Bumped every time the index is rebuilt — a scan publishing, a
    /// playlist edit — so a list that took a snapshot knows to take another.
    public private(set) var indexVersion = 0

    public private(set) var isScanning = false
    /// Files whose tags have been read in the running scan.
    public private(set) var scannedCount = 0
    /// Files the running scan found, once it has walked the folder.
    public private(set) var foundCount = 0
    /// iCloud placeholders the last scan asked the system to download.
    public private(set) var pendingDownloadCount = 0
    /// Progress of the pass that reads the tags of songs still in iCloud,
    /// once a scan has listed them. The total is set the moment the pass
    /// is queued, so nothing following it sees a gap between the scan
    /// ending and the first read.
    public private(set) var cloudTagsRead = 0
    public private(set) var cloudTagsTotal = 0
    public var isReadingCloudTags: Bool { cloudTagsTotal > 0 }

    /// Whether songs still in iCloud have their tags read without being
    /// downloaded: on Wi‑Fi, a read of just each file's header. Off, they
    /// list by name and folder until they come down.
    public var readsCloudTags = true {
        didSet {
            defaults.set(readsCloudTags, forKey: AppStorageKeys.filesReadCloudTags)
            if readsCloudTags {
                readCloudTagsIfNeeded()
            } else {
                cloudTagTask?.cancel()
            }
        }
    }
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
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var cloudTagTask: Task<Void, Never>?
    @ObservationIgnored private var rescanRequested = false
    /// Bumped when the folder changes, so a scan of the old folder that is
    /// still winding down can't publish into the new one.
    @ObservationIgnored private var folderGeneration = 0
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// Called on the main actor as a scan begins. The app hangs the
    /// continued-processing task off it, so a long scan carries on with
    /// progress on the Lock Screen after the app is backgrounded.
    @ObservationIgnored public var onScanStarted: (@MainActor () -> Void)?
    /// Called on the main actor as the pass over songs still in iCloud
    /// begins. It follows a scan most of the time, but also starts on its
    /// own when the setting is turned on, so the app hangs the same
    /// continued-processing task off it: reading a big library's tags takes
    /// far longer than listing it, and would otherwise stop with the app
    /// suspended.
    @ObservationIgnored public var onCloudTagsStarted: (@MainActor () -> Void)?

    nonisolated private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aif", "aiff", "aifc", "caf", "m4b", "alac"
    ]
    nonisolated private static let playlistExtensions: Set<String> = ["m3u", "m3u8"]

    /// A scan older than this is refreshed in the background the next time
    /// the library is opened — cheap, since unchanged files aren't re-read.
    private static let staleAfter: TimeInterval = 10 * 60

    private init() {
        folderName = defaults.string(forKey: AppStorageKeys.filesFolderName)
        readsCloudTags = defaults.object(forKey: AppStorageKeys.filesReadCloudTags) as? Bool ?? true
        resolveFolder()
        let stored = Self.loadIndex()
        tracks = stored.tracks
        filePlaylists = stored.playlists
        scheduleIndexRefresh()
    }

    /// An index over given tracks, touching neither defaults nor disk —
    /// for tests of the index, the sorts and the lookups.
    init(tracks: [FileTrack], playlists: [FilePlaylist] = [], folderURL: URL? = nil) {
        self.folderURL = folderURL
        self.folderName = folderURL?.lastPathComponent
        self.tracks = tracks
        self.filePlaylists = playlists
        catalog = FilesIndex.make(tracks: self.tracks, playlists: playlists, folderURL: folderURL, artworkDirectory: Self.artworkDirectory)
    }

    // MARK: - Folder

    private static let log = Logger(subsystem: "dance.cue", category: "files")

    /// Keeps the picked folder. `url` is the security-scoped URL a document
    /// picker hands over; the bookmark is what survives a relaunch.
    ///
    /// The folder always takes for this session: if a security-scoped
    /// bookmark can't be made (the Mac sandbox without the bookmark
    /// capability, an unusual file provider), a plain one is tried, and
    /// failing that the URL itself is kept with its access left open, and
    /// the error says so.
    public func setFolder(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        Self.log.notice("setFolder \(url.path, privacy: .public) accessed=\(accessed)")

        var bookmark: Data?
        var failure: String?
        do {
            bookmark = try url.bookmarkData(
                options: Self.bookmarkCreationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            Self.log.error("security-scoped bookmark failed: \(error.localizedDescription, privacy: .public)")
            if let plain = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                bookmark = plain
            } else {
                failure = "Cue can use this folder until it quits, but couldn't keep access to it: \(error.localizedDescription)"
            }
        }

        scanTask?.cancel()
        cloudTagTask?.cancel()
        cloudTagTask = nil
        folderGeneration += 1
        stopAccessingFolder()
        tracks = []
        filePlaylists = []
        lastScan = nil
        resetIndex()

        let name = url.lastPathComponent.isEmpty ? "Music" : url.lastPathComponent
        if let bookmark {
            defaults.set(bookmark, forKey: AppStorageKeys.filesFolderBookmark)
        } else {
            defaults.removeObject(forKey: AppStorageKeys.filesFolderBookmark)
        }
        defaults.set(name, forKey: AppStorageKeys.filesFolderName)
        folderName = name
        lastError = failure

        if bookmark != nil {
            if accessed { url.stopAccessingSecurityScopedResource() }
            resolveFolder()
            if folderURL == nil {
                // The bookmark was made but won't resolve; the URL in hand
                // still works for now.
                folderURL = url
                isAccessingFolder = url.startAccessingSecurityScopedResource()
            }
        } else {
            folderURL = url
            isAccessingFolder = accessed
        }
        Self.log.notice("folder set: \(name, privacy: .public) resolved=\(self.folderURL != nil)")
        rescan()
    }

    /// Forgets the folder and everything indexed from it.
    public func removeFolder() {
        scanTask?.cancel()
        scanTask = nil
        cloudTagTask?.cancel()
        cloudTagTask = nil
        cloudTagsTotal = 0
        cloudTagsRead = 0
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
        folderGeneration += 1
        resetIndex()
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
            Self.log.error("bookmark resolve failed: \(error.localizedDescription, privacy: .public)")
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
        await indexRefresh?.value
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

    /// Starts a scan, or asks the running one to go again when it's done.
    /// Never cancels: a scan that was cancelled midway would have to start
    /// over, and two scans of the same folder would only race.
    public func rescan() {
        if isScanning {
            rescanRequested = true
            return
        }
        scanTask = Task { await scan() }
    }

    /// Stops the running scan, and the iCloud tag pass with it. What they
    /// have read so far is kept; the next open of the library picks up the
    /// rest.
    public func cancelScan() {
        scanTask?.cancel()
        cloudTagTask?.cancel()
    }

    public func scan() async {
        guard let folderURL else {
            Self.log.error("scan requested with no folder")
            return
        }
        if isScanning {
            rescanRequested = true
            return
        }
        isScanning = true
        scannedCount = 0
        foundCount = 0
        let generation = folderGeneration
        defer {
            isScanning = false
            if rescanRequested {
                rescanRequested = false
                scanTask = Task { await self.scan() }
            }
        }
        Self.log.notice("scan started: \(folderURL.path, privacy: .public)")
        onScanStarted?()

        let root = folderURL
        let artworkDirectory = Self.artworkDirectory
        try? FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)

        // Walking a big folder is file I/O; keep it off the main actor.
        let walk = await Task.detached(priority: .userInitiated) {
            Self.walkFolder(root)
        }.value
        guard generation == folderGeneration else { return }
        foundCount = walk.files.count + walk.placeholders.count
        pendingDownloadCount = walk.placeholders.count

        let previous = Dictionary(tracks.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })

        // Files still in iCloud are listed by name and folder layout until
        // they come down; opening one would make iCloud fetch it, and a
        // scan is not the place to download a library.
        let placeholders = walk.placeholders.map { url -> FileTrack in
            // One that was here and left again — evicted after streaming,
            // or removed from the device — keeps the tags read while it was
            // down; only the bytes went.
            if var old = previous[Self.relativePath(of: url, in: root)] {
                old.isDownloaded = false
                return old
            }
            var track = FileTrack(
                relativePath: Self.relativePath(of: url, in: root),
                title: url.deletingPathExtension().lastPathComponent,
                fileExtension: url.pathExtension.lowercased(),
                isDownloaded: false,
                tagsRead: false
            )
            Self.applyFolderLayout(to: &track, url: url, root: root, titleFromFileName: true)
            return track
        }

        // Only files that changed since the last scan have their tags read
        // again; the rest keep what they had.
        let (kept, toRead) = Self.partitionForRescan(walk.files, previous: previous, root: root)
        let total = kept.count + toRead.count
        var scanned = kept.count
        scannedCount = scanned

        // What's known so far goes up straight away, so the library fills
        // in while the tags are read rather than appearing all at once.
        await publish(kept + placeholders, playlists: filePlaylists, generation: generation, final: false)

        // Tags are read a few files at a time: AVFoundation opens each file,
        // and a folder can hold thousands.
        var read: [FileTrack] = []
        var next = 0
        var sincePublish = 0
        await withTaskGroup(of: FileTrack?.self) { group in
            let width = min(6, toRead.count)
            while next < width {
                let entry = toRead[next]
                next += 1
                group.addTask { await Self.readTrack(entry, root: root, artworkDirectory: artworkDirectory) }
            }
            while let result = await group.next() {
                if let result { read.append(result) }
                // Ten at a time: a count that moves per file re-renders the
                // progress text for every song.
                scanned += 1
                if scanned % 10 == 0 || scanned == total { scannedCount = scanned }
                sincePublish += 1
                if Task.isCancelled { group.cancelAll() }
                if sincePublish >= 100 {
                    sincePublish = 0
                    await publish(kept + read + placeholders, playlists: filePlaylists, generation: generation, final: false)
                }
                if next < toRead.count, !Task.isCancelled {
                    let entry = toRead[next]
                    next += 1
                    group.addTask { await Self.readTrack(entry, root: root, artworkDirectory: artworkDirectory) }
                }
            }
        }
        guard generation == folderGeneration else { return }

        if Task.isCancelled {
            // Keep what was read; the unread files list by name for now and
            // the next scan reads their tags.
            let unread = toRead.dropFirst(read.count).map { entry -> FileTrack in
                var track = FileTrack(
                    relativePath: Self.relativePath(of: entry.url, in: root),
                    title: entry.url.deletingPathExtension().lastPathComponent,
                    fileExtension: entry.url.pathExtension.lowercased(),
                    isDownloaded: false,
                    tagsRead: false
                )
                Self.applyFolderLayout(to: &track, url: entry.url, root: root, titleFromFileName: true)
                return track
            }
            await publish(kept + read + Array(unread) + placeholders, playlists: filePlaylists, generation: generation, final: false)
            Self.log.notice("scan cancelled after \(read.count) of \(toRead.count)")
            return
        }

        let all = kept + read + placeholders
        let known = Set(all.map(\.relativePath))
        let playlists = await Task.detached(priority: .userInitiated) {
            Self.readPlaylists(walk.playlists, root: root, knownPaths: known)
        }.value
        guard generation == folderGeneration else { return }

        await publish(all, playlists: playlists, generation: generation, final: true)
        Self.log.notice("scan finished: \(all.count) tracks, \(playlists.count) playlists, \(walk.placeholders.count) in iCloud only")
        readCloudTagsIfNeeded()
    }

    /// Takes `tracks` as the library and asks for the index to follow. A
    /// final publish waits for it, stamps the scan and writes the index to
    /// disk; an interim one returns at once and lets the builds coalesce.
    private func publish(_ tracks: [FileTrack], playlists: [FilePlaylist], generation: Int, final: Bool) async {
        guard generation == folderGeneration else { return }
        self.tracks = tracks
        filePlaylists = playlists
        if final {
            lastScan = .now
            await refreshIndexNow(persist: true)
        } else {
            scheduleIndexRefresh()
        }
    }

    struct FolderWalk: Sendable {
        struct Entry: Sendable {
            var url: URL
            var modificationDate: Date?
            var fileSize: Int?
        }
        var files: [Entry] = []
        var placeholders: [URL] = []
        var playlists: [URL] = []
    }

    /// Splits a walk into the files whose tags can be kept from the last
    /// scan and the ones to read again: a file is re-read when it is new,
    /// was only a placeholder before, or changed size or modification date.
    nonisolated static func partitionForRescan(
        _ files: [FolderWalk.Entry],
        previous: [String: FileTrack],
        root: URL
    ) -> (kept: [FileTrack], toRead: [FolderWalk.Entry]) {
        var kept: [FileTrack] = []
        var toRead: [FolderWalk.Entry] = []
        for entry in files {
            let path = relativePath(of: entry.url, in: root)
            if let old = previous[path], old.isDownloaded,
               old.modificationDate == entry.modificationDate, old.fileSize == entry.fileSize {
                kept.append(old)
            } else {
                toRead.append(entry)
            }
        }
        return (kept, toRead)
    }

    /// Every audio file and playlist under `root`. Files still in iCloud are
    /// reported separately, by the URL the real file has: the old
    /// `.name.ext.icloud` placeholders, and the dataless files newer iCloud
    /// Drive lists under their real names — which look like ordinary files
    /// but make iCloud fetch them the moment they're opened.
    nonisolated static func walkFolder(_ root: URL) -> FolderWalk {
        var walk = FolderWalk()
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .contentModificationDateKey, .fileSizeKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ]
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
                        walk.placeholders.append(real)
                    }
                }
                continue
            }

            guard values?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            let isDataless = values?.isUbiquitousItem == true
                && values?.ubiquitousItemDownloadingStatus != nil
                && values?.ubiquitousItemDownloadingStatus != .current
            if audioExtensions.contains(ext) {
                if isDataless {
                    walk.placeholders.append(url)
                } else {
                    walk.files.append(.init(url: url, modificationDate: values?.contentModificationDate, fileSize: values?.fileSize))
                }
            } else if playlistExtensions.contains(ext), !isDataless {
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

        // Cue's own reader first: it knows the FLAC, WAV and AIFF tags
        // AVFoundation leaves out, and reads only the bytes the tags are in.
        var artworkData = apply(parseTags(url: url, fileSize: entry.fileSize), to: &track, titleFromFileName: &titleFromFileName)
        // AVFoundation fills whatever that left — a format it doesn't
        // cover, or a file with little in its tags.
        if titleFromFileName || track.artist == nil || track.album == nil || track.duration == nil {
            let fromAVFoundation = await readWithAVFoundation(url: url, into: &track, titleFromFileName: &titleFromFileName)
            artworkData = artworkData ?? fromAVFoundation
        }
        track.tagsRead = true

        applyFolderLayout(to: &track, url: url, root: root, titleFromFileName: titleFromFileName)

        if let artworkData {
            storeArtwork(artworkData, for: &track, in: artworkDirectory)
        }
        return track
    }

    nonisolated static func parseTags(url: URL, fileSize: Int?) -> AudioTags? {
        guard let source = try? FileTagSource(url: url, length: fileSize) else { return nil }
        defer { source.close() }
        return try? TagReader.read(from: source)
    }

    /// Puts what the tags say onto the track. A tag's value wins over what
    /// was there — a placeholder's folder-layout guesses, most often.
    /// Returns the embedded cover for the caller to store.
    @discardableResult
    nonisolated static func apply(_ tags: AudioTags?, to track: inout FileTrack, titleFromFileName: inout Bool) -> Data? {
        guard let tags else { return nil }
        if let title = tags.title {
            track.title = title
            titleFromFileName = false
        }
        track.artist = tags.artist ?? track.artist
        track.albumArtist = tags.albumArtist ?? track.albumArtist
        track.album = tags.album ?? track.album
        track.genre = tags.genre ?? track.genre
        track.year = tags.year ?? track.year
        track.trackNumber = tags.trackNumber ?? track.trackNumber
        track.discNumber = tags.discNumber ?? track.discNumber
        track.duration = tags.duration ?? track.duration
        // A compilation with no album artist of its own is Various Artists,
        // so its songs stay one album rather than one per artist.
        if tags.isCompilation, track.albumArtist == nil {
            track.albumArtist = "Various Artists"
        }
        guard let artwork = tags.artwork, !artwork.isEmpty else { return nil }
        return artwork
    }

    /// One cover per album, written the first time it's seen.
    nonisolated static func storeArtwork(_ data: Data, for track: inout FileTrack, in artworkDirectory: URL) {
        let fileName = hash("\(track.groupingArtist)|\(track.albumTitle)") + ".img"
        let file = artworkDirectory.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: file.path) {
            try? data.write(to: file)
        }
        track.artworkFileName = fileName
    }

    /// AVFoundation's reading, filling only what is still missing.
    nonisolated private static func readWithAVFoundation(url: URL, into track: inout FileTrack, titleFromFileName: inout Bool) async -> Data? {
        let asset = AVURLAsset(url: url)
        var artworkData: Data?

        if let common = try? await asset.load(.commonMetadata) {
            for item in common {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if titleFromFileName, let value = try? await item.load(.stringValue), !value.isEmpty {
                        track.title = value
                        titleFromFileName = false
                    }
                case .commonKeyArtist:
                    if track.artist == nil { track.artist = nonEmpty(try? await item.load(.stringValue)) }
                case .commonKeyAlbumName:
                    if track.album == nil { track.album = nonEmpty(try? await item.load(.stringValue)) }
                case .commonKeyType:
                    if track.genre == nil { track.genre = nonEmpty(try? await item.load(.stringValue)) }
                case .commonKeyCreationDate:
                    if track.year == nil, let value = try? await item.load(.stringValue) { track.year = year(from: value) }
                case .commonKeyArtwork:
                    if artworkData == nil { artworkData = try? await item.load(.dataValue) }
                default:
                    break
                }
            }
        }

        if track.duration == nil, let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 {
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
        return artworkData
    }

    /// The layout fallback. Folders above the file stand in for missing
    /// tags — `Artist/Album/Song.mp3`, or `Artist/Album/Disc 2/Song.mp3` —
    /// and a leading number on the file name is the track number, with the
    /// rest as the title when the tags had none.
    nonisolated static func applyFolderLayout(to track: inout FileTrack, url: URL, root: URL, titleFromFileName: Bool) {
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
        if let match = fileName.firstMatch(of: #/^\s*(?:(\d)[-.])?(\d{1,3})\s*[-._)]?\s+(.+)$/#) {
            if track.trackNumber == nil { track.trackNumber = Int(match.2) }
            if track.discNumber == nil, let disc = match.1 { track.discNumber = Int(disc) }
            if titleFromFileName {
                let rest = String(match.3).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { track.title = rest }
            }
        }
    }

    nonisolated static func discNumber(fromFolder name: String) -> Int? {
        guard let match = name.firstMatch(of: #/^(?:disc|disk|cd)\s*(\d{1,2})$/#.ignoresCase()) else { return nil }
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
    nonisolated static func packedNumber(from value: any NSCopying & NSObjectProtocol) -> Int? {
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
    nonisolated static func year(from string: String) -> Int? {
        // No lookbehind in Swift Regex: "start or a non-digit" does the job.
        guard let match = string.firstMatch(of: #/(?:^|\D)(\d{4})(?!\d)/#) else { return nil }
        let value = Int(match.1) ?? 0
        return (1900...2100).contains(value) ? value : nil
    }

    nonisolated static func nonEmpty(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Reads each `.m3u` as the tracks it names, resolved against the
    /// playlist's own folder (or the root for absolute paths) and kept only
    /// where the scan found the file.
    nonisolated static func readPlaylists(_ urls: [URL], root: URL, knownPaths: Set<String>) -> [FilePlaylist] {
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

    nonisolated static func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    nonisolated static func hash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Index

    /// What the lists read. Built off the main actor by `FilesIndex.build`
    /// and replaced whole; every read of it here is tracked, so a swap
    /// re-renders whatever is showing.
    private var catalog = FilesIndex.empty
    @ObservationIgnored private var indexRefresh: Task<Void, Never>?
    @ObservationIgnored private var indexDirty = false
    @ObservationIgnored private var indexPersistPending = false

    /// Asks for the index to be rebuilt from `tracks` and `filePlaylists`.
    /// Requests coalesce: one build runs at a time, a request during a
    /// build queues exactly one more, and while a scan is running builds
    /// are a second apart at most — a fast reader can't keep the main
    /// actor busy swapping indexes.
    private func scheduleIndexRefresh(persist: Bool = false) {
        indexDirty = true
        if persist { indexPersistPending = true }
        guard indexRefresh == nil else { return }
        indexRefresh = Task { [weak self] in
            guard let self else { return }
            while self.indexDirty {
                self.indexDirty = false
                let persist = self.indexPersistPending
                self.indexPersistPending = false
                let tracks = self.tracks
                let playlists = self.filePlaylists
                let folderURL = self.folderURL
                let generation = self.folderGeneration
                let built = await FilesIndex.build(tracks: tracks, playlists: playlists, folderURL: folderURL, artworkDirectory: Self.artworkDirectory)
                guard generation == self.folderGeneration else { break }
                self.catalog = built
                self.indexVersion += 1
                if persist {
                    await Self.persistIndex(tracks: tracks, playlists: playlists)
                }
                if self.isScanning, self.indexDirty {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            self.indexRefresh = nil
        }
    }

    /// A refresh the caller waits for — a scan's last publish, a playlist
    /// edit. Cancelling the task skips only its pacing sleep; the build
    /// itself always runs to the swap.
    private func refreshIndexNow(persist: Bool = false) async {
        scheduleIndexRefresh(persist: persist)
        indexRefresh?.cancel()
        await indexRefresh?.value
    }

    /// The folder is gone or changed: nothing to show, and a build still
    /// running is for the old generation and won't land.
    private func resetIndex() {
        indexDirty = false
        indexPersistPending = false
        catalog = .empty
        indexVersion += 1
    }

    @concurrent
    nonisolated private static func persistIndex(tracks: [FileTrack], playlists: [FilePlaylist]) async {
        saveIndex(tracks: tracks, playlists: playlists)
    }

    // MARK: - Lookups

    public func track(id: String) -> PlayableContent? { catalog.songsByID[id] }
    public func album(id: String) -> PlayableContent? { catalog.albumsByID[id] }
    public func artist(id: String) -> PlayableContent? { catalog.artistsByID[id] }

    public func playlist(id: String) -> PlayableContent? {
        id == Self.allSongsID ? allSongsContainer : catalog.playlistsByID[id]
    }

    /// An album's songs in play order: disc and track number where the tags
    /// or file names have them, title otherwise.
    public func albumTracks(albumID: String) -> [PlayableContent] {
        let ids = catalog.songIDsByAlbum[albumID] ?? []
        return ids.compactMap { catalog.songsByID[$0] }.sorted { lhs, rhs in
            let l = catalog.tracksByID[lhs.content.id]
            let r = catalog.tracksByID[rhs.content.id]
            let lDisc = l?.discNumber ?? 1
            let rDisc = r?.discNumber ?? 1
            if lDisc != rDisc { return lDisc < rDisc }
            switch (l?.trackNumber, r?.trackNumber) {
            case let (a?, b?) where a != b: return a < b
            case (nil, .some): return false
            case (.some, nil): return true
            default: return NaturalSortKey.key(for: lhs.title) < NaturalSortKey.key(for: rhs.title)
            }
        }
    }

    public func artistAlbums(artistID: String) -> [PlayableContent] {
        (catalog.albumIDsByArtist[artistID] ?? []).compactMap { catalog.albumsByID[$0] }
            .map { ($0, NaturalSortKey.key(for: $0.title)) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Every song by an artist, album by album.
    public func artistTracks(artistID: String) -> [PlayableContent] {
        artistAlbums(artistID: artistID).flatMap { albumTracks(albumID: $0.content.id) }
    }

    /// A playlist's songs in the order the file lists them; the All Songs
    /// container is the whole library by title.
    public func playlistTracks(playlistID: String) -> [PlayableContent] {
        if playlistID == Self.allSongsID { return songs }
        return (catalog.songIDsByPlaylist[playlistID] ?? []).compactMap { catalog.songsByID[$0] }
    }

    /// A page of songs in one of the offered orders. Every order was sorted
    /// when the index was built, so a page is a slice.
    public func songs(sortedBy sort: SongSort = .title, descending: Bool = false, offset: Int, limit: Int = 200) -> [PlayableContent] {
        let order = catalog.songOrder(sort, descending: descending)
        return order.dropFirst(max(0, offset)).prefix(limit).map { catalog.songs[$0] }
    }

    public func albums(sortedBy sort: AlbumSort = .title, descending: Bool = false) -> [PlayableContent] {
        catalog.albumOrder(sort, descending: descending).map { catalog.albums[$0] }
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

        let paths = [track].compactMap { $0 }.compactMap { catalog.tracksByID[$0.content.id]?.relativePath }
        let playlist = FilePlaylist(
            relativePath: Self.relativePath(of: url, in: folderURL),
            title: safeName,
            trackRelativePaths: paths
        )
        guard await write(playlist) else { return nil }
        filePlaylists.append(playlist)
        await commitPlaylists()
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
        await commitPlaylists()
        return self.playlist(id: id)
    }

    public func deletePlaylist(id: String) async -> Bool {
        guard let folderURL, let index = playlistIndex(id: id) else { return false }
        let url = folderURL.appendingPathComponent(filePlaylists[index].relativePath)
        guard await Task.detached(priority: .userInitiated, operation: { Self.coordinatedDelete(url) }).value else { return false }
        filePlaylists.remove(at: index)
        await commitPlaylists()
        return true
    }

    public func addToPlaylist(trackID: String, playlistID: String) async -> Bool {
        guard let index = playlistIndex(id: playlistID), let track = catalog.tracksByID[trackID] else { return false }
        var playlist = filePlaylists[index]
        playlist.trackRelativePaths.append(track.relativePath)
        guard await write(playlist) else { return false }
        filePlaylists[index] = playlist
        await commitPlaylists()
        return true
    }

    /// Removes one occurrence: the one at `position` when it is that track,
    /// otherwise the first.
    public func removeFromPlaylist(trackID: String, playlistID: String, position: Int? = nil) async -> Bool {
        guard let index = playlistIndex(id: playlistID), let track = catalog.tracksByID[trackID] else { return false }
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
        await commitPlaylists()
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
        await commitPlaylists()
        return true
    }

    private func commitPlaylists() async {
        await refreshIndexNow(persist: true)
    }

    /// Writes a playlist as Extended M3U — a `#PLAYLIST:` name, an `#EXTINF`
    /// line per song, and paths relative to the file — coordinated so an
    /// iCloud Drive folder sees one clean replacement.
    private func write(_ playlist: FilePlaylist) async -> Bool {
        guard let folderURL else { return false }
        let url = folderURL.appendingPathComponent(playlist.relativePath)
        var tracksByPath: [String: FileTrack] = [:]
        for path in playlist.trackRelativePaths {
            if let id = catalog.songIDByPath[path], let track = catalog.tracksByID[id] { tracksByPath[path] = track }
        }
        let data = Data(Self.m3uText(for: playlist, tracksByPath: tracksByPath).utf8)
        return await Task.detached(priority: .userInitiated) { Self.coordinatedWrite(data, to: url) }.value
    }

    /// The Extended M3U for a playlist: a `#PLAYLIST:` name, an `#EXTINF`
    /// line for each song the index knows, and every path relative to the
    /// playlist's own folder. A path the index doesn't know is written
    /// bare, so nothing the user listed is dropped.
    nonisolated static func m3uText(for playlist: FilePlaylist, tracksByPath: [String: FileTrack]) -> String {
        let directory = (playlist.relativePath as NSString).deletingLastPathComponent
        var lines = ["#EXTM3U", "#PLAYLIST:\(playlist.title)"]
        for path in playlist.trackRelativePaths {
            if let track = tracksByPath[path] {
                let seconds = Int((track.duration ?? -1).rounded())
                lines.append("#EXTINF:\(seconds),\(track.artist ?? track.groupingArtist) - \(track.title)")
            }
            lines.append(relativePath(from: directory, to: path))
        }
        return lines.joined(separator: "\n") + "\n"
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
    nonisolated static func relativePath(from directory: String, to path: String) -> String {
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
        guard isCloudFolder, let track = catalog.tracksByID[trackID], let folderURL else { return .notCloud }
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
        catalog.songIDByPath[path].flatMap { catalog.songsByID[$0] }
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

    /// Songs the user asked for by name — Download Everything, a row's
    /// download — as opposed to ones fetched to play. Streaming evicts
    /// behind itself; these it leaves alone.
    public private(set) var keptTrackIDs: Set<String> = FilesLibraryService.loadKept()

    public func isKept(trackID: String) -> Bool {
        keptTrackIDs.contains(trackID)
    }

    /// Asks iCloud for the files. The system carries the transfer itself,
    /// app suspended or not, and the scan notices when they land.
    ///
    /// `keep` marks them as the user's own downloads, which streaming
    /// never evicts; the playback cache passes `false` for what it fetches
    /// to play.
    public func downloadFromCloud(trackIDs: [String], keep: Bool = true) {
        guard let folderURL else { return }
        for id in trackIDs {
            guard let track = catalog.tracksByID[id] else { continue }
            try? FileManager.default.startDownloadingUbiquitousItem(at: folderURL.appendingPathComponent(track.relativePath))
        }
        if keep {
            keptTrackIDs.formUnion(trackIDs)
            Self.saveKept(keptTrackIDs)
        }
        startCloudMonitor()
    }

    /// Takes streamed copies off the device — only ones the user didn't
    /// ask to keep. Returns the ids it evicted.
    @discardableResult
    public func evictStreamed(trackIDs: [String]) -> [String] {
        let evictable = trackIDs.filter { !keptTrackIDs.contains($0) }
        guard !evictable.isEmpty else { return [] }
        removeFromDevice(trackIDs: evictable)
        return evictable
    }

    /// Flips the index for files that just left the device, so rows and
    /// the player see them as in iCloud again without a full rescan.
    private func markNotDownloaded(trackIDs: [String]) {
        let paths = Set(trackIDs.compactMap { catalog.tracksByID[$0]?.relativePath })
        guard !paths.isEmpty else { return }
        var changed = false
        for position in tracks.indices where paths.contains(tracks[position].relativePath) && tracks[position].isDownloaded {
            tracks[position].isDownloaded = false
            changed = true
        }
        guard changed else { return }
        pendingDownloadCount = tracks.filter { !$0.isDownloaded }.count
        scheduleIndexRefresh(persist: true)
    }

    /// Every song not on this device. Returns the ids it asked for, so the
    /// caller can follow them.
    @discardableResult
    public func downloadAllFromCloud() -> [String] {
        let ids = tracks.compactMap { track -> String? in
            let id = Self.hash("song|\(track.relativePath)")
            return cloudStatus(trackID: id) == .notDownloaded ? id : nil
        }
        downloadFromCloud(trackIDs: ids)
        return ids
    }

    /// Hands the space back; the files stay in iCloud and list as before,
    /// tags included.
    public func removeFromDevice(trackIDs: [String]) {
        guard let folderURL else { return }
        for id in trackIDs {
            guard let track = catalog.tracksByID[id] else { continue }
            try? FileManager.default.evictUbiquitousItem(at: folderURL.appendingPathComponent(track.relativePath))
        }
        keptTrackIDs.subtract(trackIDs)
        Self.saveKept(keptTrackIDs)
        markNotDownloaded(trackIDs: trackIDs)
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
                if let id = catalog.songIDByPath[relative], catalog.tracksByID[id]?.isDownloaded == false { landed = true }
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

    // MARK: - Tags of songs still in iCloud

    /// Starts the pass that reads the tags of songs still in iCloud, when
    /// the setting allows it and something is left unread. Each read asks
    /// for the tag bytes only; on a system that fetches a cloud file in
    /// parts, that is all that comes down. Where the whole file came down
    /// to serve the read, it is evicted again unless the user had asked
    /// for it — the library ends the pass no bigger than it started.
    public func readCloudTagsIfNeeded() {
        guard readsCloudTags, isCloudFolder, cloudTagTask == nil, let folderURL else { return }
        let pending = tracks.filter { !$0.hasReadTags }
        guard !pending.isEmpty else { return }
        let generation = folderGeneration
        // Counted from here rather than from the first read: a scan calls
        // this as its last step, and whatever follows the scan's progress
        // must see the pass as under way before the scan reports done.
        cloudTagsTotal = pending.count
        cloudTagsRead = 0
        cloudTagTask = Task { [weak self] in
            await self?.readCloudTags(pending, folderURL: folderURL, generation: generation)
            self?.cloudTagTask = nil
        }
        onCloudTagsStarted?()
    }

    private struct CloudTagResult: Sendable {
        var relativePath: String
        var tags: AudioTags?
        /// True when the read left the whole file on the device and the
        /// user had asked for it, so it stays.
        var isLocalNow: Bool
    }

    private func readCloudTags(_ pending: [FileTrack], folderURL: URL, generation: Int) async {
        defer {
            cloudTagsTotal = 0
            cloudTagsRead = 0
        }
        guard await NetworkConditions.isUnmetered() else {
            Self.log.notice("cloud tags: waiting for Wi‑Fi, \(pending.count) unread")
            return
        }
        guard generation == folderGeneration, !Task.isCancelled else { return }
        Self.log.notice("cloud tags: reading \(pending.count)")
        let root = folderURL
        let artworkDirectory = Self.artworkDirectory
        let kept = keptTrackIDs
        let positions = Dictionary(tracks.enumerated().map { ($0.element.relativePath, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var sincePublish = 0
        var changed = false

        // Two at a time: each read may block while the system fetches.
        let jobs = pending.map { track in
            (url: root.appendingPathComponent(track.relativePath),
             keep: kept.contains(Self.hash("song|\(track.relativePath)")))
        }
        await withTaskGroup(of: CloudTagResult.self) { group in
            var next = 0
            while next < min(2, jobs.count) {
                let job = jobs[next]
                next += 1
                group.addTask { Self.readCloudTag(url: job.url, root: root, keep: job.keep) }
            }
            while let result = await group.next() {
                cloudTagsRead += 1
                if generation != folderGeneration || Task.isCancelled {
                    group.cancelAll()
                    continue
                }
                if let position = trackPosition(ofPath: result.relativePath, hint: positions[result.relativePath]) {
                    var track = tracks[position]
                    var titleFromFileName = true
                    if let artwork = Self.apply(result.tags, to: &track, titleFromFileName: &titleFromFileName) {
                        Self.storeArtwork(artwork, for: &track, in: artworkDirectory)
                    }
                    track.tagsRead = true
                    if result.isLocalNow { track.isDownloaded = true }
                    tracks[position] = track
                    changed = true
                    sincePublish += 1
                }
                if sincePublish >= 25 {
                    sincePublish = 0
                    scheduleIndexRefresh()
                }
                if next < jobs.count, !Task.isCancelled {
                    let job = jobs[next]
                    next += 1
                    group.addTask { Self.readCloudTag(url: job.url, root: root, keep: job.keep) }
                }
            }
        }
        guard generation == folderGeneration, changed else { return }
        pendingDownloadCount = tracks.filter { !$0.isDownloaded }.count
        await refreshIndexNow(persist: true)
        Self.log.notice("cloud tags: done")
    }

    /// The track at a path: the position noted when the pass began where
    /// it still holds, else a search, since a scan may have republished.
    private func trackPosition(ofPath path: String, hint: Int?) -> Int? {
        if let hint, tracks.indices.contains(hint), tracks[hint].relativePath == path { return hint }
        return tracks.firstIndex { $0.relativePath == path }
    }

    nonisolated private static func readCloudTag(url: URL, root: URL, keep: Bool) -> CloudTagResult {
        let path = relativePath(of: url, in: root)
        var tags: AudioTags?
        if let source = try? FileTagSource(url: url) {
            tags = try? TagReader.read(from: source)
            source.close()
        }
        // If the system brought the whole file down to serve the read, hand
        // the space back — unless the user had asked for this song.
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        var isLocal = status == .current
        if isLocal, !keep {
            try? FileManager.default.evictUbiquitousItem(at: url)
            isLocal = false
        }
        return CloudTagResult(relativePath: path, tags: tags, isLocalNow: isLocal)
    }

    // MARK: - Storage

    private struct StoredIndex: Codable {
        var tracks: [FileTrack]
        var playlists: [FilePlaylist]
    }

    nonisolated private static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("FilesLibrary", isDirectory: true)
    }

    nonisolated private static var indexURL: URL {
        supportDirectory.appendingPathComponent("index.json")
    }

    nonisolated private static var artworkDirectory: URL {
        supportDirectory.appendingPathComponent("Artwork", isDirectory: true)
    }

    nonisolated private static var keptURL: URL {
        supportDirectory.appendingPathComponent("kept.json")
    }

    nonisolated private static func loadKept() -> Set<String> {
        guard let data = try? Data(contentsOf: keptURL),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    nonisolated private static func saveKept(_ ids: Set<String>) {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Array(ids).sorted()) else { return }
        try? data.write(to: keptURL, options: .atomic)
    }

    nonisolated private static func loadIndex() -> (tracks: [FileTrack], playlists: [FilePlaylist]) {
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

    nonisolated private static func saveIndex(tracks: [FileTrack], playlists: [FilePlaylist]) {
        try? FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(StoredIndex(tracks: tracks, playlists: playlists)) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
