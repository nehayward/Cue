#if os(iOS) && !targetEnvironment(macCatalyst)
import CarPlay
import Defaults
import Foundation
import Nuke
import OSLog
import SonosKit
import UIKit

/// Plays what's picked on the car's screen.
///
/// On this device, whatever the phone was last pointed at: something picked
/// in the car is meant to be heard in the car. The route is moved to this
/// device without carrying anything, so whatever was playing elsewhere is
/// left as it was — someone may still be listening there.
///
/// Unless the car drives a speaker (`CarSpeakerControl`: the speakers in
/// reach from the car, as parked at home, and one picked in CarPlay since it
/// connected): then a pick plays on that speaker, through
/// the phone's own funnel (`PlayDestinationRouter`), as a tap on the phone
/// would with the speaker chosen. A Files song still plays here, as no
/// speaker can reach it.
@MainActor
enum CarPlayPlayback {
    /// `log stream --predicate 'subsystem == "dance.cue" AND category == "carplay"' --level debug`
    private static let log = Logger(subsystem: "dance.cue", category: "carplay")

    /// Plays `contents` from the top, containers expanded in place.
    static func play(_ contents: [PlayableContent], shuffle: Bool = false) async throws {
        guard let first = contents.first else { return }
        if let group = try speaker() {
            log.notice("play \(first.content.id, privacy: .public) count=\(contents.count) shuffle=\(shuffle) on \(group.nameWithCount, privacy: .public)")
            // Only Play and Shuffle set the speaker's shuffle: a song or a
            // station picked on its own leaves it as it is.
            let setsShuffle = shuffle || contents.count > 1 || !first.content.type.isTrack && !first.content.type.isRadio
            await playOnSpeaker(contents, position: position(for: first), shuffle: setsShuffle ? shuffle : nil) { group, position in
                if contents.count == 1 {
                    return QueueItem(playableContent: first, group: group, position: position, showBanner: false)
                }
                return nil
            } queueAll: { group in
                try await SonosService.shared.queue(contents: contents, group: group, position: .replace, startIndex: 0)
            }
            return
        }
        takeRoute()
        log.notice("play \(first.content.id, privacy: .public) count=\(contents.count) shuffle=\(shuffle)")
        try await LocalPlaybackService.shared.enqueue(contents, at: .now, shuffle: shuffle)
        record(first)
    }

    /// Plays `items` from `index` on, as a list of songs: a song picked in
    /// the downloads' Songs list plays the list from there.
    static func play(_ items: [PlayableContent], startingAt index: Int) async throws {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        if let group = try speaker() {
            log.notice("play \(item.content.id, privacy: .public) at \(index) of \(items.count) on \(group.nameWithCount, privacy: .public)")
            await playOnSpeaker(items, position: .replace, shuffle: nil) { _, _ in nil } queueAll: { group in
                try await SonosService.shared.queue(contents: items, group: group, position: .replace, startIndex: index)
            }
            return
        }
        takeRoute()
        log.notice("play \(item.content.id, privacy: .public) at \(index) of \(items.count)")
        try await LocalPlaybackService.shared.play(items, startingAt: index)
        record(item)
    }

    /// Plays `container` from `track` on, the way a tap on a song in an
    /// album or playlist does on the phone. Falls back to the song alone
    /// when the container no longer holds it. On a speaker the container
    /// goes as one, from `index`, the song's place among the rows the car
    /// listed (`CarPlayLibrary.tracks(in:)`, which leaves out only what
    /// can't play here, so it's the container's own place but for those).
    static func play(_ track: PlayableContent, in container: PlayableContent, at index: Int? = nil) async throws {
        if let group = try speaker() {
            log.notice("play \(track.content.id, privacy: .public) in \(container.content.id, privacy: .public) on \(group.nameWithCount, privacy: .public)")
            let item = index == nil ? track : container
            await playOnSpeaker([track], position: position(for: item), shuffle: nil, from: container) { group, position in
                QueueItem(playableContent: item, group: group, position: position, index: index, showBanner: false)
            } queueAll: { _ in }
            return
        }
        takeRoute()
        log.notice("play \(track.content.id, privacy: .public) in \(container.content.id, privacy: .public)")
        let player = LocalPlaybackService.shared
        let played = try await player.play(track, in: container)
        if !played {
            try await player.enqueue([track], at: .now, from: container)
        }
        record(track)
    }

    /// Plays a book from where it was left, through the book player, which
    /// keeps its place and puts it in Recently Played: on this device, or on
    /// the speaker the car drives. Throws when it didn't start, for the car
    /// to say so.
    static func play(book: PlayableContent) async throws {
        let books = AudiobookPlayer.shared
        if let group = try speaker() {
            log.notice("play book \(book.content.id, privacy: .public) on \(group.nameWithCount, privacy: .public)")
            await PlaybackRoute.shared.endHandOff()
            await books.play(book, on: .group(group))
            guard books.current?.book.isSameBook(as: book) == true else {
                throw Failure(errorDescription: "Couldn't play “\(book.title)” on \(group.nameWithCount)")
            }
            return
        }
        takeRoute()
        log.notice("play book \(book.content.id, privacy: .public)")
        await books.play(book, on: .device)
        guard books.current?.book.isSameBook(as: book) == true, books.contains(LocalPlaybackService.shared.nowPlaying) else {
            throw Failure(errorDescription: "Couldn't play “\(book.title)”")
        }
    }

    // MARK: - On a speaker

    /// The speaker the car drives, for a pick to play on rather than here;
    /// nil plays here. Without Super only the free tier's one group plays,
    /// as on the phone, whose paywall the car can't show, so it says so.
    private static func speaker() throws -> GroupRoom? {
        guard let group = CarSpeakerControl.shared.group else { return nil }
        guard FeatureGate.shared.isGroupUnlocked(group.coordinatorID) else {
            throw Failure(errorDescription: "Playing on \(group.nameWithCount) needs Cue Super")
        }
        return group
    }

    /// Where a pick goes in the speaker's queue: as a tap on the phone puts
    /// it (Settings ▸ Playback's default play action).
    private static func position(for content: PlayableContent) -> QueuePosition {
        QueuePosition.defaultPosition(
            for: content.content.type,
            replaceQueueByDefault: UserDefaults.standard.bool(forKey: AppStorageKeys.defaultPlayAction)
        )
    }

    /// Plays on the speaker the car drives through `PlayDestinationRouter`,
    /// as the phone's rows do: it ends a hand-off still under way, parks this
    /// iPhone's queue, and plays here what only plays here. The speaker gets
    /// `item`'s queue item through `QueueManager`, which records the play and
    /// holds time asked of iOS until the speaker has it, else `queueAll`
    /// (a list of songs). `shuffle` nil leaves the speaker's own as it is.
    ///
    /// Waits a moment for the speaker to have it, up to 3 s, so the row's
    /// spinner stays until the speaker starts rather than Now Playing coming
    /// up on the song before; a long list goes on filling in behind.
    private static func playOnSpeaker(
        _ contents: [PlayableContent],
        position: QueuePosition,
        shuffle: Bool?,
        from origin: PlayableContent? = nil,
        item: @escaping (GroupRoom, QueuePosition) -> QueueItem?,
        queueAll: @escaping (GroupRoom) async throws -> Void
    ) async {
        let send = SpeakerSend()
        await PlayDestinationRouter.play(contents, position: position, shuffle: shuffle ?? false, from: origin) { group, position in
            send.isSent = true
            if let shuffle {
                await Self.setShuffle(shuffle, on: group)
            }
            if var queued = item(group, position) {
                queued.done = { send.landed = true }
                QueueManager.shared.addToQueue(item: queued)
            } else {
                Task {
                    await withBackgroundTime(named: "Queue on speaker from CarPlay") {
                        do {
                            try await queueAll(group)
                        } catch {
                            Self.log.error("queue on \(group.nameWithCount, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                    send.landed = true
                }
            }
        }
        guard send.isSent else { return }
        let deadline = ContinuousClock.now + .seconds(3)
        while !send.landed, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    /// Whether, and when, a speaker was given a pick.
    @MainActor
    private final class SpeakerSend {
        var isSent = false
        var landed = false
    }

    /// Shuffle on or off on `group`, as Play and Shuffle ask.
    private static func setShuffle(_ shuffle: Bool, on group: GroupRoom) async {
        var mode = group.playMode
        if shuffle {
            mode.insert(.shuffle)
        } else {
            mode.remove(.shuffle)
        }
        guard mode != group.playMode else { return }
        await SonosService.shared.setPlayMode(group.ip, mode: mode)
        group.playMode = mode
    }

    /// The speeds a car's rate button steps through, back to normal after
    /// the last: fewer than the phone's menu, for a tap at a time.
    static let bookRates: [Double] = [1, 1.2, 1.5, 1.75, 2]

    /// Moves the book's speed on to the next of `bookRates`.
    static func nextBookRate() {
        let books = AudiobookPlayer.shared
        let next = bookRates.first { $0 > books.rate + 0.01 } ?? 1
        log.notice("book rate \(books.rate) → \(next)")
        books.setRate(next)
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// Plays the device's queue from where it stopped: just paused, or
    /// restored from the last launch or parked by a hand-off with nothing
    /// armed yet, which Play arms at the saved spot (a book's files at the
    /// book's kept place, `AudiobookPlayer.resumeOnDevice`).
    static func resume() {
        let player = LocalPlaybackService.shared
        guard player.isActive else { return }
        takeRoute()
        guard !player.isPlaying else { return }
        log.notice("resume \(player.nowPlaying?.content.id ?? "-", privacy: .public)")
        player.togglePlayback()
    }

    /// Points the route at this device if it's elsewhere. See the type's
    /// comment for why nothing is carried. A play here means the car is no
    /// longer driving a speaker (Resume on the device's queue, or one gone
    /// out of reach), so it lets go of it, after the switch: let go first,
    /// the route would already read this device, and the switch would find
    /// nothing to do.
    private static func takeRoute() {
        let route = PlaybackRoute.shared
        if route.destination != .device {
            log.notice("route → device for a play from CarPlay")
            route.switchTo(.device, carrying: false)
        }
        CarSpeakerControl.shared.release()
    }

    /// Into Recently Played, the same as a play from the phone — see
    /// `PlayDestinationRouter.record`. Not Shuffle All over the downloads:
    /// On This Device is a way to play, not something to go back to.
    private static func record(_ item: PlayableContent) {
        guard !OnDeviceLibrary.isAllSongs(item) else { return }
        let history = PlayHistoryService.shared
        history.history.remove(item)
        history.history.insert(item, at: 0)
    }
}

/// Artwork for the car's lists, through the shared Nuke pipeline under the
/// key the phone's artwork views use, so a cover already seen there usually
/// comes straight from the cache.
@MainActor
enum CarPlayArtwork {
    /// Comfortably over `CPListItem.maximumImageSize` on any car's screen;
    /// the system scales it down.
    static let rowWidth: CGFloat = 120
    /// For the cards and squares of an image row, and the details header's
    /// thumbnail.
    static let cardWidth: CGFloat = 400

    /// The car's screen, for its light or dark look (see `symbol(_:)`).
    static weak var screen: CPInterfaceController?

    /// Sets `content`'s cover on `item` once it's loaded. The row keeps its
    /// placeholder symbol until then, and for good when there's no cover.
    static func load(_ content: PlayableContent, into item: CPListItem) {
        load(content, width: rowWidth) { [weak item] image in
            item?.setImage(image)
        }
    }

    /// Hands `content`'s cover to `apply` once it's loaded — at once when
    /// it's cached. Never called when there's no cover or it won't load.
    static func load(_ content: PlayableContent, width: CGFloat, _ apply: @escaping @MainActor (UIImage) -> Void) {
        // A book shows its Audible edition's cover, as on the phone.
        let content = ContentArtworkView.drawnContent(for: content)
        guard let url = content.thumbnail ?? content.artwork else { return }
        var request = ImageRequest(url: url, processors: [.resize(width: width)])
        request.imageID = content.imageKey
        if let cached = ImagePipeline.shared.cache.cachedImage(for: request)?.image {
            apply(cached)
            return
        }
        Task {
            guard let image = try? await ImagePipeline.shared.image(for: request) else { return }
            apply(image)
        }
    }

    /// A cover by its address: a speaker's song, which has no content of
    /// Cue's to go by (Home's row for the speaker the car drives).
    static func load(url: URL, width: CGFloat, _ apply: @escaping @MainActor (UIImage) -> Void) {
        let request = ImageRequest(url: url, processors: [.resize(width: width)])
        if let cached = ImagePipeline.shared.cache.cachedImage(for: request)?.image {
            apply(cached)
            return
        }
        Task {
            guard let image = try? await ImagePipeline.shared.image(for: request) else { return }
            apply(image)
        }
    }

    /// What a row shows before its cover arrives: the content type's symbol.
    static func placeholder(for content: PlayableContent) -> UIImage? {
        symbol(content.content.type.symbol)
    }

    /// The same, never nil, for the APIs that won't take a missing image.
    static func requiredPlaceholder(for content: PlayableContent) -> UIImage {
        placeholder(for: content) ?? symbol("music.note") ?? UIImage()
    }

    /// A system symbol in white on a dark screen and black on a light one
    /// (`looks`). The car tints the tab bar's symbols but draws a row's as
    /// it gets them, and a plain symbol is black.
    static func symbol(_ name: String) -> UIImage? {
        guard let symbol = UIImage(systemName: name) else { return nil }
        return looks { color in symbol.withTintColor(color, renderingMode: .alwaysOriginal) }
    }

    /// A tile's symbol (`CarPlayInterface.tileRow`), drawn whole in the
    /// middle of a square the size the car draws a tile's image at. The car
    /// resizes what it's given to that square, which would stretch a symbol
    /// that isn't square (most aren't), and a bare symbol fills it edge to
    /// edge. White and black, as `symbol(_:)`.
    static func tile(_ name: String) -> UIImage {
        let maximum = CPListImageRowItemCondensedElement.maximumImageSize
        let side = min(maximum.width, maximum.height) > 0 ? min(maximum.width, maximum.height) : 44
        let configuration = UIImage.SymbolConfiguration(pointSize: side / 2, weight: .medium)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return UIImage() }
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(screen?.carTraitCollection.displayScale ?? 2, 1)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        // A little over half the square, whichever way the symbol is longer.
        let fit = min(1, side * 0.6 / max(symbol.size.width, symbol.size.height, 1))
        let size = CGSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
        let frame = CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height)
        return looks { color in
            renderer.image { _ in
                symbol.withTintColor(color, renderingMode: .alwaysOriginal).draw(in: frame)
            }
        }
    }

    /// The queue's button on the car's Now Playing, and a book's chapters':
    /// the place, the song's in the queue or the chapter's in the book, as a
    /// number in a circle ("5.circle"). Zero under a station, which leaves
    /// the queue waiting, as a speaker's reads on radio. The symbols stop at
    /// 50; past that it's a list.
    ///
    /// A plain system symbol, which the car recolours and draws the size of
    /// its own buttons. The phone's ring drawn as a bitmap (`QueueIconView`'s
    /// fill and number) came out a dot in a car on iOS 27, a fraction of the
    /// size of the rate button beside it, though it was drawn at
    /// `CPNowPlayingButtonMaximumImageSize` at the car's scale; on the list
    /// buttons the car draws nothing but a plain symbol (FB24806621).
    static func placeButton(_ place: Int) -> UIImage {
        let name = (0...50).contains(place) ? "\(place).circle" : "list.bullet"
        return UIImage(systemName: name) ?? UIImage(systemName: "list.bullet") ?? UIImage()
    }

    /// An image in black for a light screen and white for a dark one, both
    /// in its asset, for the car to switch as it goes from day to night; the
    /// one handed over is the screen's look now.
    private static func looks(_ draw: (UIColor) -> UIImage) -> UIImage {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let asset = UIImageAsset()
        asset.register(draw(.black), with: UITraitCollection(userInterfaceStyle: .light))
        asset.register(draw(.white), with: dark)
        return asset.image(with: screen?.carTraitCollection ?? dark)
    }
}
#endif
