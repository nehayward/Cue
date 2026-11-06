import Foundation
import MusicSearchKit
import OSLog
import SonosKit
import UIKit
import WatchSync

/// Each book's place in iCloud's key-value store (`CloudBookPlaces`), so a
/// book left on one of the listener's devices picks up on the others: the
/// Mac, the iPhone, the iPad, and the Apple Watch, which reads and writes
/// the same store for the books on it (`WatchBookStore`).
///
/// Every book this device keeps a place in (`AudiobookProgressStore`) goes
/// up, Plex's, Audiobookshelf's and Files' alike, so it works without a
/// server keeping places too: Files books have none, and Plex keeps a place
/// within a file only with Store track progress on. A minute after the
/// first change while a book plays, a few seconds after a pause (the moment
/// the listener may pick it up elsewhere), and as Cue leaves the screen or
/// quits. Read at launch, on coming back to Cue and whenever iCloud brings
/// a change.
///
/// What comes down is kept where it's newer (`WatchBookPlace.supersedes`)
/// and this device is signed in to the book's server: the book picks up
/// here where it was left there, this device's own place stays in the
/// book's history (named for the device that took over), and the book
/// loaded here but paused gives way (`AudiobookPlayer.notePlaceMoved`), so
/// Play starts from the new place. A book playing here keeps playing: its
/// own place, newer, is the one the others hear. Its server hears of the
/// new place when the book next opens (`AudiobookLibrary.sendNewerPlace`).
///
/// The watch's places also come with its picks, through WatchConnectivity
/// (`WatchSyncService`), which notes them here (`noteTaken`).
@MainActor
final class BookPlaceSync {
    static let shared = BookPlaceSync()

    private let cloud = CloudBookPlaces()
    private let logger = Logger(subsystem: "dance.cue", category: "audiobooks")
    private var observers: [NSObjectProtocol] = []
    private var shareTask: Task<Void, Never>?
    private var isStarted = false
    /// Places this device holds only because another device's came in
    /// (iCloud's, the watch's, or the server's), by
    /// `AudiobookProgressStore.key`, this launch: they're that device's to
    /// put up, not this one's, and when a newer place replaces one there's
    /// no place of this device's to keep in the book's history.
    private var taken: [String: AudiobookProgress] = [:]

    /// The services whose books have places kept: those with books.
    private static let services: Set<MusicService> = [.plex, .audiobookshelf, .files]

    /// How long a playing book's place waits to go up after it first
    /// moves: places move every few seconds while a book plays.
    private static let listeningDelay: Duration = .seconds(60)
    /// How long a pause waits: the reading that follows it lands first.
    private static let pauseDelay: Duration = .seconds(3)

    private init() {}

    /// Follows iCloud's places, once, at launch.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        let center = NotificationCenter.default
        let store = NSUbiquitousKeyValueStore.default
        observers = [
            center.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reconcile() }
            },
            // Coming back to Cue: what iCloud brought while it was away.
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    _ = NSUbiquitousKeyValueStore.default.synchronize()
                    self?.reconcile()
                }
            },
            // Leaving Cue (on the Mac, another app coming to the front): a
            // place still waiting goes now. In a task, so the player keeps
            // what it heard first (`AudiobookPlayer.flush`).
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.shareIfWaiting() }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.share() }
            },
            // Quitting (the Mac): no task would run.
            center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.share()
                    _ = NSUbiquitousKeyValueStore.default.synchronize()
                }
            },
        ]
        store.synchronize()
        reconcile()
    }

    // MARK: - Up

    /// A book's place moved here (`AudiobookProgressStore.record`): iCloud
    /// hears a minute after the first change, unless a pause or leaving Cue
    /// sends it sooner.
    func placesDidChange() {
        guard isStarted, shareTask == nil else { return }
        scheduleShare(after: Self.listeningDelay)
    }

    /// A book paused here: the other devices hear in a few seconds, as the
    /// listener may be about to pick it up on one of them.
    func bookPaused() {
        guard isStarted else { return }
        shareTask?.cancel()
        scheduleShare(after: Self.pauseDelay)
    }

    private func scheduleShare(after delay: Duration) {
        shareTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.share()
        }
    }

    private func shareIfWaiting() {
        guard shareTask != nil else { return }
        share()
    }

    /// This device's places up, where they're newer than iCloud's.
    private func share() {
        shareTask?.cancel()
        shareTask = nil
        guard isStarted else { return }
        let (places, books) = ownPlaces()
        let written = cloud.write(places, books: books, device: Self.device)
        if !written.isEmpty {
            logger.info("iCloud: put up \(written.count) book places")
        }
    }

    /// The places this device keeps of its own, by the book's key in iCloud
    /// (`CloudBookPlaces.bookKey`), with which book each is. Not those taken
    /// from another device this launch: that device puts them up itself.
    private func ownPlaces() -> (WatchBookPlaces, [String: CloudBookPlaces.CloudBook]) {
        var places = WatchBookPlaces.empty
        var books: [String: CloudBookPlaces.CloudBook] = [:]
        for (key, reading) in AudiobookProgressStore.shared.readings {
            guard taken[key] != reading,
                  let book = AudiobookProgressStore.book(forKey: key), Self.services.contains(book.service) else { continue }
            let identity = CloudBookPlaces.CloudBook(service: book.service.sonosRawValue, id: book.id)
            let bookKey = CloudBookPlaces.bookKey(service: identity.service, id: identity.id)
            places.record(WatchBookPlace(reading), for: bookKey)
            books[bookKey] = identity
        }
        return (places, books)
    }

    // MARK: - Down

    /// iCloud's places in, where they're newer than this device's, and this
    /// device's up, where they're newer than iCloud's: what was there may
    /// have been an older place that reached iCloud last.
    private func reconcile() {
        guard isStarted else { return }
        let known = knownBooks()
        for entry in cloud.readAll() {
            // A place from before books were named (an older watch's) is
            // taken only for a book this device knows.
            guard let identity = entry.identity ?? known[entry.book],
                  let service = MusicService(service: identity.service),
                  Self.services.contains(service), Self.isSignedIn(to: service) else { continue }
            take(entry.place, service: service, id: identity.id, from: entry.device)
        }
        share()
    }

    /// The books this device knows by their key in iCloud: those it keeps a
    /// place in, and those picked for the watch.
    private func knownBooks() -> [String: CloudBookPlaces.CloudBook] {
        var known: [String: CloudBookPlaces.CloudBook] = [:]
        for key in AudiobookProgressStore.shared.readings.keys {
            guard let book = AudiobookProgressStore.book(forKey: key) else { continue }
            let identity = CloudBookPlaces.CloudBook(service: book.service.sonosRawValue, id: book.id)
            known[CloudBookPlaces.bookKey(service: identity.service, id: identity.id)] = identity
        }
        for pick in WatchSyncService.shared.picks.items where pick.kind == .audiobook {
            known[pick.key] = CloudBookPlaces.CloudBook(service: pick.source.rawValue, id: pick.id)
        }
        return known
    }

    /// One book's place from another device, kept where it's newer than
    /// this device's.
    private func take(_ place: WatchBookPlace, service: MusicService, id: String, from device: CloudBookPlaces.Device?) {
        let store = AudiobookProgressStore.shared
        let book = Self.book(service: service, id: id)
        let held = store.progress(for: book)
        if let held, !place.supersedes(WatchBookPlace(held)) { return }
        let player = AudiobookPlayer.shared
        let loaded = player.current.flatMap { $0.book.isSameBook(as: book) ? $0.book : nil }
        let controller = PlaybackRoute.shared.controller
        if loaded != nil, controller.isPlaying, player.isPlayingBook(on: controller) { return }
        let reading = AudiobookProgress(place)
        if let held, !isTaken(held, for: book), !held.isFinished, held.position > 0, abs(held.position - reading.position) > 60 {
            AudiobookPlaceHistory.shared.record(.replaced, at: held.position, to: reading.position, for: book, from: device.map(AudiobookPlaceHistory.Place.Source.init(device:)))
        }
        logger.info("iCloud: \(service.sonosRawValue, privacy: .public) book \(id, privacy: .public): the place from \(device?.rawValue ?? "another device", privacy: .public), \(Int(reading.position)) s, is newer")
        noteTaken(reading, for: book)
        store.record(reading, for: book)
        if let loaded {
            Task { await player.notePlaceMoved(loaded, to: reading) }
        }
    }

    /// Notes a place another device gave `book` (the watch's, through
    /// WatchConnectivity), or its server did, so it isn't put up as this
    /// device's, nor kept in the book's history as this device's when a
    /// newer one replaces it.
    func noteTaken(_ reading: AudiobookProgress, for book: PlayableContent) {
        noteTaken(reading, key: AudiobookProgressStore.key(for: book))
    }

    /// The same, for a book known by its `AudiobookProgressStore.key`.
    func noteTaken(_ reading: AudiobookProgress, key: String) {
        taken[key] = reading
    }

    /// Whether `reading` is a place another device gave `book` this launch.
    func isTaken(_ reading: AudiobookProgress, for book: PlayableContent) -> Bool {
        taken[AudiobookProgressStore.key(for: book)] == reading
    }

    // MARK: - Helpers

    /// Only for a server this device is signed in to: a sign-out forgets
    /// that account's places (`AudiobookProgressStore.forgetAll`), and
    /// iCloud mustn't bring them back. Files books are this device's own.
    private static func isSignedIn(to service: MusicService) -> Bool {
        switch service {
        case .plex: !(PlexAuthenticator.shared.authToken ?? "").isEmpty
        case .audiobookshelf: AudiobookshelfAPI.shared.isConfigured
        case .files: true
        default: false
        }
    }

    /// The book `service` and `id` name, as this device's stores know it.
    private static func book(service: MusicService, id: String) -> PlayableContent {
        PlayableContent(
            title: "",
            subtitle: "",
            thumbnail: nil,
            artwork: nil,
            content: .init(service: service, id: id, type: .audiobook, location: nil)
        )
    }

    /// The kind of device this is, for the other devices' history.
    private static var device: CloudBookPlaces.Device {
        #if targetEnvironment(macCatalyst)
        return .mac
        #elseif os(visionOS)
        return .vision
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
    }
}

extension AudiobookPlaceHistory.Place.Source {
    /// The device a place in iCloud came from.
    init(device: CloudBookPlaces.Device) {
        switch device {
        case .iPhone: self = .iPhone
        case .iPad: self = .iPad
        case .mac: self = .mac
        case .watch: self = .watch
        case .vision: self = .vision
        }
    }
}
