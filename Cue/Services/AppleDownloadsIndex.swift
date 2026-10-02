import Foundation
import MusicKit
import Observation
import SonosKit

#if os(iOS)
import MediaPlayer
#endif
#if canImport(UIKit)
import UIKit
#endif

/// The Apple Music songs the Music app holds a downloaded copy of, so Cue
/// can list them under Downloaded, fold them into the on-device library
/// for Offline Mode, and badge them in lists.
///
/// Third-party apps can't download Apple Music tracks themselves (the files
/// are DRM'd and the API to initiate a download doesn't exist), but the
/// library can be asked for just its downloaded songs — a
/// `MusicLibraryRequest` with `includeOnlyDownloadedContent` — on every
/// platform, and `ApplicationMusicPlayer` plays those with no network. So
/// while Cue can't *make* a track downloaded, it can show the ones that
/// are, and play them.
///
/// Three keys answer "is this downloaded?": the library id the request
/// returns (what Apple library rows carry), the catalog id (what search
/// results and the catalog's albums carry — the media library maps a
/// downloaded song to it on iOS through `playbackStoreID`), and the ISRC,
/// which both sides carry and is the one that also works on the Mac.
@MainActor
@Observable
final class AppleDownloadsIndex {
    static let shared = AppleDownloadsIndex()

    /// Every downloaded song as a library track, by title. Nothing until
    /// Apple Music is authorized.
    private(set) var songs: [PlayableContent] = []

    /// Bumped each time `songs` is replaced, for the lists that took a
    /// snapshot to know to take another.
    private(set) var version = 0

    private var libraryIDs: Set<String> = []
    private var catalogIDs: Set<String> = []
    private var isrcs: Set<String> = []
    /// When each song joined the library, by library id, for the
    /// recency sort.
    private var addedDates: [String: Date] = [:]

    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var foregroundObserver: (any NSObjectProtocol)?

    /// How long a sweep stays good for. Menus and screens ask on every
    /// appearance; this keeps that from being a library walk each time.
    private static let refreshInterval: TimeInterval = 30

    private init() {
        refreshIfNeeded()
#if canImport(UIKit)
        // Downloads happen in the Music app, so what's here can only have
        // changed while Cue was away.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppleDownloadsIndex.shared.refreshIfNeeded(force: true)
            }
        }
#endif
    }

    func isDownloaded(_ item: PlayableContent) -> Bool {
        guard item.content.service == .apple, item.content.type.isTrack else { return false }
        if libraryIDs.contains(item.content.id) || catalogIDs.contains(item.content.id) { return true }
        if let isrc = item.metadata?.isrc, !isrc.isEmpty { return isrcs.contains(isrc) }
        return false
    }

    /// When a downloaded song was added to the library, or nil for one
    /// this index doesn't hold.
    func addedDate(for item: PlayableContent) -> Date? {
        addedDates[item.content.id]
    }

    /// Rebuilds the index off the main thread. Skipped while a sweep is
    /// running or the last one is fresh, unless forced.
    func refreshIfNeeded(force: Bool = false) {
        guard !isRefreshing else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.refreshInterval { return }
        guard MusicAuthorization.currentStatus == .authorized else { return }
        isRefreshing = true
        Task.detached(priority: .utility) {
            let snapshot = await Self.sweep()
            await MainActor.run {
                let index = AppleDownloadsIndex.shared
                index.apply(snapshot)
                index.isRefreshing = false
                index.lastRefresh = Date()
            }
        }
    }

    // MARK: - Sweep

    private func apply(_ snapshot: AppleDownloadsSnapshot) {
        let changed = snapshot.libraryIDs != libraryIDs || snapshot.catalogIDs != catalogIDs
        songs = snapshot.songs
        libraryIDs = snapshot.libraryIDs
        catalogIDs = snapshot.catalogIDs
        isrcs = snapshot.isrcs
        addedDates = snapshot.addedDates
        if changed { version &+= 1 }
    }

    nonisolated private static func sweep() async -> AppleDownloadsSnapshot {
        var snapshot = AppleDownloadsSnapshot()

        var request = MusicLibraryRequest<Song>()
        request.includeOnlyDownloadedContent = true
        if let items = try? await request.response().items {
            var songs: [PlayableContent] = []
            songs.reserveCapacity(items.count)
            for song in items {
                let track = song.toPlayableLibraryTrack
                songs.append(track)
                snapshot.libraryIDs.insert(track.content.id)
                if let isrc = song.isrc, !isrc.isEmpty { snapshot.isrcs.insert(isrc) }
                if let added = song.libraryAddedDate { snapshot.addedDates[track.content.id] = added }
            }
            snapshot.songs = songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }

#if os(iOS)
        // The media library is the one place a downloaded song's catalog id
        // is exposed, which is what a search result is badged by.
        if MPMediaLibrary.authorizationStatus() == .authorized {
            snapshot.catalogIDs = Set(
                (MPMediaQuery.songs().items ?? [])
                    .filter { !$0.isCloudItem && $0.playbackStoreID != "0" }
                    .map(\.playbackStoreID)
            )
        }
#endif

        return snapshot
    }
}

/// One sweep's result, built off the main thread and applied on it.
private struct AppleDownloadsSnapshot: Sendable {
    var songs: [PlayableContent] = []
    var libraryIDs: Set<String> = []
    var catalogIDs: Set<String> = []
    var isrcs: Set<String> = []
    var addedDates: [String: Date] = [:]
}
