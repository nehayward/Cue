#if os(iOS) && !targetEnvironment(macCatalyst)
import CarPlay
import Defaults
import MediaPlayer
import MusicSearchKit
import Observation
import SonosKit
import UIKit

/// Cue on a car's screen: four tabs and the system's Now Playing.
///
/// - **Recents** — what was last played in Cue, with Resume on top when the
///   device has a queue waiting.
/// - **Library** — the signed-in providers' library, a section at a time:
///   Playlists, Recently Added and Albums are a switch across the top, and
///   the section shows under it as grids of covers.
/// - **Downloads** — what's on this iPhone, which plays with no signal:
///   Shuffle All, Albums, Artists and Songs, and the newest albums.
/// - **Radio** — TuneIn's and Apple Music's stations, as on the phone, as
///   grids of squares.
///
/// Everything plays on this device (see `CarPlayPlayback`); speakers have
/// no place in a car, so nothing here offers one. The car's Now Playing
/// screen is the system's, filled from the card the device player publishes
/// (see `LocalNowPlayingPresenter`); this adds Up Next (with shuffle and
/// repeat over it), the album or playlist that's playing, shuffle and
/// repeat to it.
///
/// The newest plays and downloads are iOS 26 card rows, the stations and
/// the Library's sections image grids, and the buttons (the Library's
/// sections, the Downloads tab's ways in, Play and Shuffle, shuffle and
/// repeat) tiles on the car's platters (`tileRow`). From iOS 27 an album or
/// playlist opens under a details header with its cover, and the system's
/// MiniPlayer shows what's playing without any work here.
///
/// The tabs are built once and refilled in place, following the player,
/// the play history and the downloads through observation.
@MainActor
final class CarPlayInterface: NSObject {
    private let interfaceController: CPInterfaceController

    private let recentsTemplate: CPListTemplate
    private let libraryTemplate: CPListTemplate
    private let downloadsTemplate: CPListTemplate
    private let radioTemplate: CPListTemplate
    private var tabBar: CPTabBarTemplate?

    /// Up Next, pushed from Now Playing, follows the player while it's up.
    private weak var upNextTemplate: CPListTemplate?
    /// What Now Playing's buttons were last set to show (`updateNowPlaying`);
    /// nil until they've been set this connection.
    private var nowPlayingButtons: String?

    private var isConnected = false
    private var radioTask: Task<Void, Never>?
    /// The Library tab's section while it loads; nil once it's in.
    private var libraryTask: Task<Void, Never>?
    /// The providers the Library tab was last filled from. The player's
    /// changes, which come often, don't fetch the section again; a
    /// provider coming or going, or the tab being picked, does.
    private var libraryServices: [MediaSearchService]?
    /// The section the Library tab shows under its switch.
    private var librarySection = ProviderCollection.playlists
    /// What each section last loaded, so switching back to one is instant.
    /// Emptied when the providers change.
    private var libraryShelves: [ProviderCollection: [CarPlayLibrary.Shelf]] = [:]
    /// The on-device library's change token the Downloads tab was last
    /// filled at. Grouping a big library isn't free, and the player's
    /// changes, which come often, don't move it.
    private var downloadsToken: Int?

    /// CarPlay refuses a push past this many templates, root included.
    private static let maximumDepth = 5

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        recentsTemplate = CarPlayInterface.tab(title: "Recents", image: UIImage(systemName: "clock"))
        libraryTemplate = CarPlayInterface.tab(title: "Library", image: UIImage(systemName: "square.stack"))
        downloadsTemplate = CarPlayInterface.tab(title: "Downloads", image: UIImage(systemName: "arrow.down.circle"))
        radioTemplate = CarPlayInterface.tab(title: "Radio", image: UIImage(systemName: "dot.radiowaves.left.and.right"))
        super.init()
    }

    private static func tab(title: String, image: UIImage?) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [])
        template.tabTitle = title
        template.tabImage = image
        return template
    }

    // MARK: - Lifecycle

    func start() {
        isConnected = true
        CarPlayArtwork.screen = interfaceController
        // The car's Now Playing reads this app's own card; Apple Music needs
        // one there too (see `publishesAppleMusicCard`).
        LocalPlaybackService.shared.publishesAppleMusicCard = true
        // No `upNextTitle`: with one the queue button is that word, and
        // without it the car draws its own queue icon, as for Apple Music.
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.add(self)

        guard FeatureGate.shared.isAvailable(.carPlay) else {
            showUnavailable()
            return
        }

        let tabBar = CPTabBarTemplate(templates: tabs)
        tabBar.delegate = self
        self.tabBar = tabBar
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)

        // The Music app's downloads, for the Downloads tab: with no window
        // opened this launch, nothing else has built the index.
        AppleDownloadsIndex.shared.refreshIfNeeded()
        reloadRecents()
        reloadLibrary()
        reloadDownloads()
        reloadRadio()
        updateNowPlaying()
        // With no signal, what's on this iPhone is all that will play.
        if OfflineMode.shared.isActive {
            tabBar.select(downloadsTemplate)
        }
        observe()
    }

    func stop() {
        isConnected = false
        nowPlayingButtons = nil
        LocalPlaybackService.shared.publishesAppleMusicCard = false
        CPNowPlayingTemplate.shared.remove(self)
        radioTask?.cancel()
        libraryTask?.cancel()
        libraryTask = nil
    }

    /// Radio last: a car with room for fewer tabs leaves it out first, and
    /// it's the one tab that can't play without a network.
    private var tabs: [CPTemplate] {
        let tabs: [CPTemplate] = [recentsTemplate, libraryTemplate, downloadsTemplate, radioTemplate]
        return Array(tabs.prefix(CPTabBarTemplate.maximumTabCount))
    }

    /// The gate is free today; this is what a locked one shows.
    private func showUnavailable() {
        let template = CPListTemplate(title: "Cue", sections: [])
        template.emptyViewTitleVariants = ["CarPlay Needs Cue Super"]
        template.emptyViewSubtitleVariants = ["Open Cue on your iPhone to subscribe."]
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
    }

    // MARK: - Following the player

    /// Re-arms after every change, for as long as the car is connected — the
    /// same shape as `LiveTranscriptionService.observePlayback()`.
    private func observe() {
        guard isConnected else { return }
        withObservationTracking {
            trackedState()
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.isConnected else { return }
                self.stateChanged()
                self.observe()
            }
        }
    }

    /// Reads everything the car's screens follow, so the tracking registers
    /// on it. `progress` is deliberately absent: it ticks, and nothing here
    /// draws it — Now Playing has the system's own clock.
    private func trackedState() {
        let player = LocalPlaybackService.shared
        _ = player.queue
        _ = player.currentIndex
        _ = player.isPlaying
        _ = player.isShuffled
        _ = player.repeatMode
        _ = player.source
        // What the Up Next list and the buttons switch on; `source` reads
        // it too, but not as anything to rely on.
        _ = player.isPlayingStation
        // A queue the phone handed to a speaker earlier is parked, not
        // playing; the route says which.
        _ = PlaybackRoute.shared.destination
        _ = PlayHistoryService.shared.history
        _ = OnDeviceLibrary.changeToken
        // Library empties when the network goes, and says where to look.
        _ = OfflineMode.shared.isActive
    }

    private func stateChanged() {
        updateNowPlaying()
        reloadRecents()
        reloadLibrary()
        reloadDownloads()
        if let upNextTemplate {
            fillUpNext(upNextTemplate)
        }
        updatePlayingIndicators()
    }

    /// Marks the row of what's playing on every list up, the way the Music
    /// app does. Rows carry their content's id in `userInfo` for this; a
    /// grid of stations carries its stations' ids, and the one playing gets
    /// a speaker under it.
    private func updatePlayingIndicators() {
        let player = LocalPlaybackService.shared
        let playingID = PlaybackRoute.shared.destination == .device ? player.nowPlaying?.id : nil
        var templates = interfaceController.templates
        if let tabBar {
            templates += tabBar.templates
        }
        for case let list as CPListTemplate in templates {
            for section in list.sections {
                for case let item as CPListItem in section.items {
                    guard let id = item.userInfo as? String else { continue }
                    let isPlaying = id == playingID
                    if item.isPlaying != isPlaying {
                        item.isPlaying = isPlaying
                    }
                }
                for case let grid as CPListImageRowItem in section.items {
                    guard let ids = grid.userInfo as? [String] else { continue }
                    var changed = false
                    for case let (element as CPListImageRowItemImageGridElement, id) in zip(grid.elements, ids) {
                        let symbol = id == playingID ? Self.playingSymbol : nil
                        if element.accessorySymbolName != symbol {
                            element.accessorySymbolName = symbol
                            changed = true
                        }
                    }
                    if changed {
                        // Set again so the car redraws the row.
                        grid.elements = grid.elements
                    }
                }
            }
        }
    }

    /// Under the station that's playing in a grid of them.
    private static let playingSymbol = "speaker.wave.2.fill"

    // MARK: - Recents

    /// How many of the newest plays are cards on Recents. The cards' title
    /// opens them all as a list.
    private static let recentCardCount = 10

    private func reloadRecents() {
        let player = LocalPlaybackService.shared
        let newest = Array(CarPlayLibrary.recents().prefix(Self.recentCardCount))
        // The device's queue, waiting: restored from the last launch, just
        // paused, or parked when the phone handed playback over.
        let waiting = isPlayingOnDevice ? nil : player.nowPlaying

        recentsTemplate.emptyViewTitleVariants = ["Nothing Played Yet"]
        recentsTemplate.emptyViewSubtitleVariants = ["What you play in Cue shows up here."]
        let signature = ([waiting?.id ?? ""] + newest.map(\.id)).joined(separator: "|")
        update(recentsTemplate, signature: signature) {
            var sections: [CPListSection] = []
            if let waiting {
                sections.append(CPListSection(items: [resumeRow(for: waiting)]))
            }
            if !newest.isEmpty {
                let cards = cardRow(title: "Recently Played", items: newest) { [weak self] in
                    self?.pushRecents()
                }
                sections.append(CPListSection(items: [cards]))
            }
            return sections
        }
    }

    /// Everything in Recently Played as rows, from the cards' title.
    private func pushRecents() {
        let recents = CarPlayLibrary.recents()
        let template = CPListTemplate(title: "Recently Played", sections: [])
        template.emptyViewTitleVariants = ["Nothing Played Yet"]
        let rows: [CPListTemplateItem] = recents.map { row(for: $0) }
        template.updateSections(rows.isEmpty ? [] : [CPListSection(items: rows)])
        push(template)
        updatePlayingIndicators()
    }

    private func resumeRow(for item: PlayableContent) -> CPListItem {
        let player = LocalPlaybackService.shared
        let row = CPListItem(text: "Resume", detailText: item.title, image: CarPlayArtwork.placeholder(for: item))
        CarPlayArtwork.load(item, into: row)
        // Where it stopped, as the bar a podcast app draws under an episode.
        if player.duration > 0 {
            row.playbackProgress = CGFloat(min(1, max(0, player.progress / player.duration)))
        }
        row.handler = { [weak self] _, completion in
            MainActor.assumeIsolated {
                CarPlayPlayback.resume()
                self?.showNowPlaying()
                completion()
            }
        }
        return row
    }

    // MARK: - Library

    /// The Library tab is a section at a time, with the sections as a
    /// switch of tiles across the top: picking one fills the list under
    /// them with it, from every signed-in provider, in place rather than on
    /// a screen of its own, as grids of covers like Radio's. It opens on
    /// Playlists. The tiles are up at once; a section fills in as the
    /// providers answer, and again when the tab is picked (`refresh`).
    private func reloadLibrary(refresh: Bool = false) {
        let services = CarPlayLibrary.libraryServices()
        if OfflineMode.shared.isActive {
            libraryTemplate.emptyViewTitleVariants = ["You're Offline"]
            libraryTemplate.emptyViewSubtitleVariants = ["What's on this iPhone is in Downloads."]
        } else {
            libraryTemplate.emptyViewTitleVariants = ["Nothing to Browse"]
            libraryTemplate.emptyViewSubtitleVariants = ["Set up Apple Music, Plex, Subsonic or a Files folder in Cue on your iPhone."]
        }
        // A load still under way for the same providers is left to finish:
        // picking the tab again mustn't start a slow server over.
        guard services != libraryServices || (refresh && libraryTask == nil) else { return }
        if services != libraryServices {
            libraryShelves = [:]
        }
        libraryServices = services
        loadLibrarySection()
    }

    /// Switches the list under the tiles to `section`. Picking the one
    /// that's showing reads it again, unless it's still loading.
    private func showLibrarySection(_ section: ProviderCollection) {
        guard section != librarySection || libraryTask == nil else { return }
        librarySection = section
        loadLibrarySection()
    }

    /// Shows what the section last loaded straight away and reads it again
    /// behind that. A section never loaded fills in as each provider
    /// answers; one already loaded keeps its rows until they've all
    /// answered, so a refresh doesn't drop the slower providers' shelves
    /// for a moment.
    private func loadLibrarySection() {
        libraryTask?.cancel()
        libraryTask = nil
        let services = libraryServices ?? []
        let sections = CarPlayLibrary.librarySections(for: services)
        guard !sections.isEmpty else {
            update(libraryTemplate, signature: "") { [] }
            return
        }
        if !sections.contains(librarySection), let first = sections.first {
            librarySection = first
        }
        let section = librarySection
        let shown = libraryShelves[section]
        fillLibrary(sections: sections, shelves: shown)
        libraryTask = Task { [weak self] in
            let shelves = await CarPlayLibrary.shelves(section, from: services) { soFar in
                guard shown == nil else { return }
                self?.fillLibrary(sections: sections, shelves: soFar)
            }
            guard let self, !Task.isCancelled else { return }
            self.libraryTask = nil
            self.libraryShelves[section] = shelves
            self.fillLibrary(sections: sections, shelves: shelves)
        }
    }

    /// The tiles, then the section's shelves as grids of covers, the way
    /// Radio lays out its stations: a provider's each, titled with its name
    /// when there's more than one and with the section's when there's one.
    /// `shelves` is nil while the section has nothing to show yet, and
    /// empty when it came back with nothing.
    private func fillLibrary(sections: [ProviderCollection], shelves: [CarPlayLibrary.Shelf]?) {
        let section = librarySection
        let tiles = sections.map { $0 == section ? "[\($0.rawValue)]" : $0.rawValue }.joined(separator: ",")
        let body = shelves.map { shelves in
            shelves.map { ([$0.title] + $0.items.map(\.id)).joined(separator: ",") }.joined(separator: "|")
        }
        update(libraryTemplate, signature: tiles + "/" + (body ?? "…")) {
            var list = [CPListSection(items: [libraryTiles(sections)])]
            if let shelves, !shelves.isEmpty {
                let named = shelves.count > 1
                // Room for the tiles' section.
                list += shelves.prefix(CPListTemplate.maximumSectionCount - 1).map { shelf -> CPListSection in
                    let title = named ? shelf.title : section.title
                    return CPListSection(items: [imageGrid(title: title, items: shelf.items)])
                }
            } else if shelves == nil {
                list.append(CPListSection(items: [note("Loading \(section.title)…")]))
            } else {
                list.append(CPListSection(items: [note("Nothing Here", detail: "Nothing in \(section.title) can play on this iPhone.")]))
            }
            return list
        }
        updatePlayingIndicators()
    }

    /// The Library's sections as tiles, the one showing checked.
    private func libraryTiles(_ sections: [ProviderCollection]) -> CPListImageRowItem {
        tileRow(sections.map { section in
            Tile(title: section.title, systemImage: section.systemImage, isSelected: section == librarySection, action: .run { [weak self] in
                self?.showLibrarySection(section)
            })
        })
    }

    /// Opens at once on a loading note and fills in when the provider
    /// answers: a slow server shouldn't hold the tap.
    private func pushListing(_ listing: CarPlayLibrary.Listing) {
        let template = CPListTemplate(title: listing.title, sections: [])
        template.showsSpinnerWhileEmpty = true
        push(template)
        Task { [weak self, weak template] in
            let player = LocalPlaybackService.shared
            let items = await listing.load().filter { player.canPlayAnywhereLocally($0) }
            guard let self, let template else { return }
            template.showsSpinnerWhileEmpty = false
            template.emptyViewTitleVariants = ["Nothing Here"]
            template.emptyViewSubtitleVariants = ["Nothing here can play on this iPhone."]
            var sections: [CPListSection] = []
            if let all = listing.shuffleAll, !items.isEmpty {
                sections.append(CPListSection(items: [self.playTiles(
                    play: { try await CarPlayPlayback.play(items, startingAt: 0) },
                    shuffle: { try await CarPlayPlayback.play([all], shuffle: true) }
                )]))
            }
            if !items.isEmpty {
                let limit = CarPlayLibrary.rowLimit - sections.count
                let rows: [CPListTemplateItem] = items.prefix(limit).enumerated().map { index, item in
                    guard listing.playsInOrder else { return self.row(for: item) }
                    // The whole list, not just the rows a car shows.
                    return self.row(for: item) {
                        try await CarPlayPlayback.play(items, startingAt: index)
                    }
                }
                sections.append(CPListSection(items: rows))
            }
            template.updateSections(sections)
            self.updatePlayingIndicators()
        }
    }

    /// An album's or playlist's songs, with Play and Shuffle on top. A song
    /// plays the list from there on, the way a tap in it does on the phone.
    private func pushContainer(_ container: PlayableContent) {
        let template = CPListTemplate(title: container.title, sections: [])
        template.showsSpinnerWhileEmpty = true
        push(template)
        Task { [weak self, weak template] in
            let tracks = await CarPlayLibrary.tracks(in: container)
            guard let self, let template else { return }
            template.showsSpinnerWhileEmpty = false
            template.emptyViewTitleVariants = ["No Songs"]
            template.emptyViewSubtitleVariants = ["Nothing here can play on this iPhone."]
            guard !tracks.isEmpty else {
                template.updateSections([])
                return
            }
            let play: @MainActor () async throws -> Void = { try await CarPlayPlayback.play([container]) }
            let shuffle: @MainActor () async throws -> Void = { try await CarPlayPlayback.play([container], shuffle: true) }
            var sections: [CPListSection] = []
            if #available(iOS 27.0, *) {
                self.showDetailsHeader(on: template, for: container, play: play, shuffle: shuffle)
            } else {
                sections.append(CPListSection(items: [self.playTiles(play: play, shuffle: shuffle)]))
            }
            let limit = CarPlayLibrary.rowLimit - sections.count
            let rows: [CPListTemplateItem] = tracks.prefix(limit).map { self.row(for: $0, in: container) }
            sections.append(CPListSection(items: rows))
            template.updateSections(sections)
            self.updatePlayingIndicators()
        }
    }

    /// The album or playlist at the top of its songs, the way the Music app
    /// shows one in the car: its cover, name and artist, with Play and
    /// Shuffle. The header and its thumbnail are 26.4 API, but the car only
    /// draws them from iOS 27 on, hence the check.
    @available(iOS 27.0, *)
    private func showDetailsHeader(
        on template: CPListTemplate,
        for container: PlayableContent,
        play: @escaping @MainActor () async throws -> Void,
        shuffle: @escaping @MainActor () async throws -> Void
    ) {
        let buttons = [
            actionButton(systemImage: "play.fill", play),
            actionButton(systemImage: "shuffle", shuffle),
        ].prefix(CPListTemplateDetailsHeader.maximumActionButtonCount)
        let title = container.title
        let subtitle = detail(for: container)
        func header(_ image: UIImage) -> CPListTemplateDetailsHeader {
            CPListTemplateDetailsHeader(
                thumbnail: CPThumbnailImage(image: image),
                title: title,
                subtitle: subtitle,
                actionButtons: Array(buttons)
            )
        }
        template.listHeader = header(CarPlayArtwork.requiredPlaceholder(for: container))
        let side = CPThumbnailImage.maximumImageSize(forAspectRatio: 1).width
        CarPlayArtwork.load(container, width: side > 0 ? side : CarPlayArtwork.cardWidth) { [weak template] image in
            guard let template, template.listHeader != nil else { return }
            template.listHeader = header(image)
        }
    }

    // MARK: - Downloads

    /// Shuffle All, Albums, Artists and Songs as tiles on top, then the
    /// albums that arrived last as cards. Refilled only when what's on the
    /// device has changed.
    private func reloadDownloads() {
        let token = OnDeviceLibrary.changeToken
        guard token != downloadsToken else { return }
        downloadsToken = token

        downloadsTemplate.emptyViewTitleVariants = ["No Downloads"]
        downloadsTemplate.emptyViewSubtitleVariants = [
            "Download music in Cue or the Music app on your iPhone to play it here without a connection.",
            "Download music on your iPhone to play it here.",
        ]
        guard CarPlayLibrary.hasDownloads else {
            downloadsTemplate.updateSections([])
            return
        }

        let all = CarPlayLibrary.allDownloads
        let shuffle = Tile(title: "Shuffle All", systemImage: "shuffle", action: .play {
            try await CarPlayPlayback.play([all], shuffle: true)
        })
        let browse = CarPlayLibrary.downloadListings().map { listing in
            Tile(title: listing.title, systemImage: listing.systemImage, subtitle: listing.detail, action: .run { [weak self] in
                self?.pushListing(listing)
            })
        }
        var sections = [CPListSection(items: [tileRow([shuffle] + browse)])]
        let recent = CarPlayLibrary.recentlyDownloaded()
        if !recent.isEmpty {
            let cards = cardRow(title: "Recently Downloaded", items: recent) { [weak self] in
                self?.pushListing(CarPlayLibrary.recentlyDownloadedListing)
            }
            sections.append(CPListSection(items: [cards]))
        }
        downloadsTemplate.updateSections(sections)
    }

    // MARK: - Radio

    /// Each section's stations as a grid of squares, the way the Music app
    /// lays out its radio.
    private func reloadRadio() {
        radioTask?.cancel()
        radioTemplate.showsSpinnerWhileEmpty = true
        radioTask = Task { [weak self] in
            let sections = await CarPlayLibrary.stations()
            guard let self, !Task.isCancelled else { return }
            self.radioTemplate.showsSpinnerWhileEmpty = false
            self.radioTemplate.emptyViewTitleVariants = ["No Stations"]
            self.radioTemplate.emptyViewSubtitleVariants = ["Switch on TuneIn or Apple Music in Cue on your iPhone."]
            let signature = sections
                .map { ([$0.title] + $0.stations.map(\.id)).joined(separator: ",") }
                .joined(separator: "|")
            self.update(self.radioTemplate, signature: signature) {
                sections.prefix(CPListTemplate.maximumSectionCount).map { section in
                    CPListSection(items: [self.imageGrid(title: section.title, items: section.stations)])
                }
            }
            self.updatePlayingIndicators()
        }
    }

    // MARK: - Now Playing

    /// Whether the device's own queue is what's playing — not one parked
    /// when the phone handed playback over earlier.
    private var isPlayingOnDevice: Bool {
        let player = LocalPlaybackService.shared
        return PlaybackRoute.shared.destination == .device && player.isActive && player.isPlaying
    }

    /// The album button while the device has a queue; shuffle and repeat for
    /// a queue of songs (a station has neither); and the queue button.
    ///
    /// The queue button is Cue's own, the phone's ring with the song's place
    /// in it (`CarPlayArtwork.queueGauge`), in place of the system's Up Next
    /// button, which only takes a word or the car's own icon.
    ///
    /// Runs on every change the tabs follow (a play, the history, the
    /// downloads), so each part is only handed to the car when it differs
    /// from what the car already has: every `updateNowPlayingButtons` is a
    /// new set of buttons for the car to draw.
    private func updateNowPlaying() {
        let player = LocalPlaybackService.shared
        let onDevice = PlaybackRoute.shared.destination == .device && player.isActive
        let nowPlaying = CPNowPlayingTemplate.shared
        if nowPlaying.isUpNextButtonEnabled {
            nowPlaying.isUpNextButtonEnabled = false
        }
        let albumArtist = onDevice && player.source.map { player.canPlayContainerLocally($0) } == true
        if nowPlaying.isAlbumArtistButtonEnabled != albumArtist {
            nowPlaying.isAlbumArtistButtonEnabled = albumArtist
        }

        let hasModes = onDevice && !player.isPlayingStation
        // Whenever there's a queue of songs, on its last song too, as the
        // Music app's is — and under a station, which leaves the queue
        // waiting behind it, at place zero. A station alone has no queue.
        let hasQueue = onDevice && !player.queue.isEmpty
        let signature = [
            hasModes ? "\(player.isShuffled),\(player.repeatMode.rawValue)" : "",
            hasQueue ? "\(player.queuePosition)/\(player.queueCount)" : "",
        ].joined(separator: "|")
        guard signature != nowPlayingButtons else { return }
        nowPlayingButtons = signature

        var buttons: [CPNowPlayingButton] = []
        if hasModes {
            // A tap reaches these handlers only while the matching remote
            // commands are enabled, which `LocalNowPlayingPresenter` sees
            // to. Each moves on from the state the car shows (the
            // commands' current type) rather than flipping the player's,
            // so a tap that also arrives as the command can't undo itself.
            let shuffle = CPNowPlayingShuffleButton { _ in
                MainActor.assumeIsolated {
                    let shown = MPRemoteCommandCenter.shared().changeShuffleModeCommand.currentShuffleType
                    LocalPlaybackService.shared.setShuffle(shown == .off)
                }
            }
            shuffle.isSelected = player.isShuffled
            let repeatButton = CPNowPlayingRepeatButton { _ in
                MainActor.assumeIsolated {
                    let shown = MPRemoteCommandCenter.shared().changeRepeatModeCommand.currentRepeatType
                    LocalPlaybackService.shared.setRepeatMode(LocalPlaybackService.RepeatMode(shown).next)
                }
            }
            repeatButton.isSelected = player.repeatMode != .off
            buttons += [shuffle, repeatButton]

            // What the two buttons draw their state from.
            let commands = MPRemoteCommandCenter.shared()
            commands.changeShuffleModeCommand.currentShuffleType = player.isShuffled ? .items : .off
            commands.changeRepeatModeCommand.currentRepeatType = player.repeatMode.repeatType
        }
        if hasQueue {
            let image = CarPlayArtwork.queueGauge(position: player.queuePosition, total: player.queueCount)
            buttons.append(CPNowPlayingImageButton(image: image) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.showUpNext()
                }
            })
        }
        nowPlaying.updateNowPlayingButtons(buttons)
    }

    private func showUpNext() {
        let template = CPListTemplate(title: "Up Next", sections: [])
        template.emptyViewTitleVariants = ["Nothing Up Next"]
        upNextTemplate = template
        fillUpNext(template)
        push(template)
    }

    /// Shuffle and repeat on top for a queue of songs, then what's coming.
    ///
    /// Under a station the queue waits behind it, not in use, as a speaker's
    /// does on radio: a note says so in place of the tiles, and the list is
    /// where the queue goes on from — the song it was left on, then the rest.
    /// A row picked leaves the station for the queue there.
    private func fillUpNext(_ template: CPListTemplate) {
        let player = LocalPlaybackService.shared
        let isParked = player.isPlayingStation
        let hasModes = !isParked
        let waiting = isParked ? Array(player.queue.dropFirst(player.currentIndex)) : player.upNext
        let upNext = Array(waiting.prefix(CarPlayLibrary.rowLimit - 1))
        let modes = hasModes ? "\(player.isShuffled),\(player.repeatMode.rawValue)" : "parked"
        update(template, signature: ([modes] + upNext.map(\.id)).joined(separator: "|")) {
            var sections: [CPListSection] = []
            if hasModes {
                sections.append(CPListSection(items: [playModeTiles()]))
            } else if !upNext.isEmpty {
                sections.append(CPListSection(items: [note("Not Playing", detail: "The radio is on. Pick a song to go back to the queue.")]))
            }
            guard !upNext.isEmpty else {
                // With the tiles up, the list's own empty note doesn't show.
                if hasModes {
                    sections.append(CPListSection(items: [note("Nothing Up Next")]))
                }
                return sections
            }
            let rows: [CPListTemplateItem] = upNext.map { content -> CPListTemplateItem in
                let row = CPListItem(text: content.title, detailText: detail(for: content), image: CarPlayArtwork.placeholder(for: content))
                CarPlayArtwork.load(content, into: row)
                row.handler = { [weak self] _, completion in
                    MainActor.assumeIsolated {
                        self?.jump(to: content)
                        completion()
                    }
                }
                return row
            }
            sections.append(CPListSection(items: rows))
            return sections
        }
    }

    /// Shuffle and repeat as tiles, each saying how it's set. A tile moves
    /// its mode on the way the phone's buttons do: shuffle on and off,
    /// repeat from off to all to one. The list follows the player, so the
    /// tiles and the order under them redraw on their own.
    private func playModeTiles() -> CPListImageRowItem {
        let player = LocalPlaybackService.shared
        let repeatMode = player.repeatMode
        let repeatState = switch repeatMode {
        case .off: "Off"
        case .all: "All"
        case .one: "One"
        }
        return tileRow([
            Tile(title: "Shuffle", systemImage: "shuffle", subtitle: player.isShuffled ? "On" : "Off", isSelected: player.isShuffled, action: .run {
                let player = LocalPlaybackService.shared
                player.setShuffle(!player.isShuffled)
            }),
            Tile(title: "Repeat", systemImage: repeatMode.systemImage, subtitle: repeatState, isSelected: repeatMode != .off, action: .run {
                let player = LocalPlaybackService.shared
                player.setRepeatMode(player.repeatMode.next)
            }),
        ])
    }

    /// Plays an Up Next row and goes back to Now Playing. Looked up again
    /// rather than kept as an index: the queue can have moved since the
    /// list was drawn. Under a station the song the queue was left on is
    /// listed too, and picking it goes back to its spot.
    private func jump(to content: PlayableContent) {
        let player = LocalPlaybackService.shared
        let first = player.currentIndex + (player.isPlayingStation ? 0 : 1)
        let upcoming = player.queue.indices.dropFirst(first)
        guard let index = upcoming.first(where: { player.queue[$0] == content }) else { return }
        player.play(at: index)
        interfaceController.popTemplate(animated: true, completion: nil)
    }

    private func showNowPlaying() {
        let nowPlaying = CPNowPlayingTemplate.shared
        let stack = interfaceController.templates
        if stack.last === nowPlaying { return }
        if stack.contains(where: { $0 === nowPlaying }) {
            interfaceController.pop(to: nowPlaying, animated: true, completion: nil)
        } else {
            push(nowPlaying)
        }
    }

    // MARK: - Rows

    /// A row for a song, station, album or playlist. Songs and stations play
    /// when picked — from there on in `container` when they're in one; an
    /// album or playlist opens its songs.
    private func row(for content: PlayableContent, in container: PlayableContent? = nil) -> CPListItem {
        row(for: content) {
            if let container {
                try await CarPlayPlayback.play(content, in: container)
            } else {
                try await CarPlayPlayback.play([content])
            }
        }
    }

    /// A row that runs `play` when picked, or opens its songs when it's an
    /// album or playlist the queue can't take as it is.
    private func row(for content: PlayableContent, play: @escaping @MainActor () async throws -> Void) -> CPListItem {
        let row = CPListItem(text: content.title, detailText: detail(for: content), image: CarPlayArtwork.placeholder(for: content))
        CarPlayArtwork.load(content, into: row)
        if opens(content) {
            row.accessoryType = .disclosureIndicator
        } else {
            row.userInfo = content.id
        }
        row.handler = { [weak self] _, completion in
            MainActor.assumeIsolated {
                guard let self else {
                    completion()
                    return
                }
                self.select(content, completion: completion, play)
            }
        }
        return row
    }

    /// Whether picking `content` opens its songs rather than playing it.
    private func opens(_ content: PlayableContent) -> Bool {
        !LocalPlaybackService.shared.canPlayLocally(content)
    }

    /// Opens an album or playlist, or runs `play` for anything else.
    private func select(_ content: PlayableContent, completion: @escaping () -> Void, _ play: @escaping @MainActor () async throws -> Void) {
        if opens(content) {
            pushContainer(content)
            completion()
        } else {
            perform(completion: completion, play)
        }
    }

    /// The newest of a list as a row of cards, cover on top and name under
    /// it: a song or station plays when its card is picked, an album or
    /// playlist opens. Picking the row's title runs `showAll`.
    private func cardRow(title: String, items: [PlayableContent], showAll: (@MainActor () -> Void)?) -> CPListImageRowItem {
        let elements = items.map { item in
            CPListImageRowItemCardElement(
                image: CarPlayArtwork.requiredPlaceholder(for: item),
                showsImageFullHeight: false,
                title: item.title,
                subtitle: detail(for: item),
                tintColor: nil
            )
        }
        let row = CPListImageRowItem(text: title, cardElements: elements, allowsMultipleLines: false)
        attach(items, to: row, showAll: showAll)
        return row
    }

    /// Squares in a grid: a few lines of them. The grid's title opens the
    /// rest.
    private static let squaresPerGrid = 12

    /// Stations, albums or playlists as a grid of squares with their names
    /// under them, a few lines of them: the Music app's radio and its
    /// Recently Added. A station or song plays when its square is picked,
    /// and the one playing gets a speaker under it (`updatePlayingIndicators`,
    /// from the ids in `userInfo`); an album or playlist opens, so it has
    /// nothing to mark. When there are more than fit, the grid's title opens
    /// them all as rows.
    private func imageGrid(title: String, items: [PlayableContent]) -> CPListImageRowItem {
        let shown = Array(items.prefix(Self.squaresPerGrid))
        let elements = shown.map { item in
            CPListImageRowItemImageGridElement(
                image: CarPlayArtwork.requiredPlaceholder(for: item),
                imageShape: .roundedRectangle,
                title: item.title,
                accessorySymbolName: nil
            )
        }
        let row = CPListImageRowItem(text: title, imageGridElements: elements, allowsMultipleLines: true)
        row.userInfo = shown.map { opens($0) ? "" : $0.id }
        var showAll: (@MainActor () -> Void)?
        if items.count > shown.count {
            showAll = { [weak self] in
                self?.pushRows(title: title, items: items)
            }
        }
        attach(shown, to: row, showAll: showAll)
        return row
    }

    /// All of a grid's items as rows, from its title.
    private func pushRows(title: String, items: [PlayableContent]) {
        let template = CPListTemplate(title: title, sections: [])
        let rows: [CPListTemplateItem] = items.prefix(CarPlayLibrary.rowLimit).map { row(for: $0) }
        template.updateSections([CPListSection(items: rows)])
        push(template)
        updatePlayingIndicators()
    }

    /// Loads each item's cover into its element of `row`, plays or opens the
    /// item whose element is picked, and runs `showAll` from the row's
    /// title.
    private func attach(_ items: [PlayableContent], to row: CPListImageRowItem, showAll: (@MainActor () -> Void)?) {
        for (element, item) in zip(row.elements, items) {
            CarPlayArtwork.load(item, width: CarPlayArtwork.cardWidth) { [weak row, weak element] image in
                guard let row, let element else { return }
                element.image = image
                // Set again so the car redraws the row.
                row.elements = row.elements
            }
        }
        row.listImageRowHandler = { [weak self] _, index, completion in
            MainActor.assumeIsolated {
                guard let self, items.indices.contains(index) else {
                    completion()
                    return
                }
                let item = items[index]
                self.select(item, completion: completion) {
                    try await CarPlayPlayback.play([item])
                }
            }
        }
        if let showAll {
            row.handler = { _, completion in
                MainActor.assumeIsolated {
                    showAll()
                    completion()
                }
            }
        }
    }

    /// A button in a row of them (`tileRow`): a symbol, a title and a note
    /// under it.
    private struct Tile {
        enum Action {
            /// Opens a list, switches the Library's section or sets a mode.
            case run(@MainActor () -> Void)
            /// Plays, with the tile's spinner up until it starts, then shows
            /// Now Playing.
            case play(@MainActor () async throws -> Void)
        }

        let title: String
        let systemImage: String
        var subtitle: String? = nil
        /// Checked: the section showing, or a mode that's on.
        var isSelected = false
        let action: Action
    }

    /// Buttons as tiles on the car's platters, symbol beside title, on as
    /// many lines as they need: the Music app's Library buttons (an image
    /// row of condensed elements). Not `headerGridButtons`, which the car
    /// draws as bare symbols over their titles with nothing behind them,
    /// and only for a plain system symbol on iOS 27 (FB24806621).
    private func tileRow(_ tiles: [Tile]) -> CPListImageRowItem {
        let elements = tiles.map { tile in
            CPListImageRowItemCondensedElement(
                image: CarPlayArtwork.tile(tile.systemImage),
                imageShape: .roundedRectangle,
                title: tile.title,
                subtitle: tile.subtitle,
                accessorySymbolName: tile.isSelected ? "checkmark" : nil
            )
        }
        let row = CPListImageRowItem(text: nil, condensedElements: elements, allowsMultipleLines: true)
        row.listImageRowHandler = { [weak self] _, index, completion in
            MainActor.assumeIsolated {
                guard let self, tiles.indices.contains(index) else {
                    completion()
                    return
                }
                switch tiles[index].action {
                case let .run(action):
                    action()
                    completion()
                case let .play(play):
                    self.perform(completion: completion, play)
                }
            }
        }
        return row
    }

    /// Play and Shuffle over a list of songs.
    private func playTiles(
        play: @escaping @MainActor () async throws -> Void,
        shuffle: @escaping @MainActor () async throws -> Void
    ) -> CPListImageRowItem {
        tileRow([
            Tile(title: "Play", systemImage: "play.fill", action: .play(play)),
            Tile(title: "Shuffle", systemImage: "shuffle", action: .play(shuffle)),
        ])
    }

    /// A row that only says something, such as a section still loading.
    private func note(_ text: String, detail: String? = nil) -> CPListItem {
        let row = CPListItem(text: text, detailText: detail)
        row.isEnabled = false
        return row
    }

    /// A button in a list's details header.
    private func actionButton(systemImage: String, _ play: @escaping @MainActor () async throws -> Void) -> CPButton {
        let image = UIImage(systemName: systemImage) ?? UIImage()
        return CPButton(image: image) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.perform(completion: {}, play)
            }
        }
    }

    /// The artist under a song; whatever the provider put under anything
    /// else (an album's artist, a playlist's curator, a station's genre).
    private func detail(for content: PlayableContent) -> String? {
        let text = content.content.type.isTrack ? (content.metadata?.artist ?? content.subtitle) : content.subtitle
        return text.isEmpty ? nil : text
    }

    /// Runs a play, then shows Now Playing — or says what went wrong. The
    /// row keeps its spinner until `completion`.
    private func perform(completion: @escaping () -> Void, _ play: @escaping @MainActor () async throws -> Void) {
        Task {
            defer { completion() }
            do {
                try await play()
                self.showNowPlaying()
            } catch {
                self.showAlert(error.localizedDescription)
            }
        }
    }

    // MARK: - Templates

    /// Replaces a list's rows only when what it shows has changed. The
    /// signature lives on the template, so a new list never inherits an old
    /// one's.
    private func update(_ template: CPListTemplate, signature: String, sections: () -> [CPListSection]) {
        guard (template.userInfo as? String) != signature else { return }
        template.userInfo = signature
        template.updateSections(sections())
    }

    /// Pushes, going back to the root first when the stack is as deep as
    /// CarPlay allows.
    private func push(_ template: CPTemplate) {
        if interfaceController.templates.count >= Self.maximumDepth {
            interfaceController.popToRootTemplate(animated: false, completion: nil)
        }
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    /// One alert at a time; while one is up, a second message isn't news.
    private func showAlert(_ message: String) {
        guard interfaceController.presentedTemplate == nil else { return }
        let alert = CPAlertTemplate(titleVariants: [message], actions: [
            CPAlertAction(title: "OK", style: .cancel) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.interfaceController.dismissTemplate(animated: true, completion: nil)
                }
            },
        ])
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
    }
}

// MARK: - Delegates

extension CarPlayInterface: CPTabBarTemplateDelegate {
    /// Recents and Library read state that changes off screen — a sign-in on
    /// the phone, a provider switched off, a playlist made since — so
    /// they're re-read on the way in. Downloads follow the on-device library
    /// on their own. Radio is loaded once, and again if it came up empty.
    func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        if selectedTemplate === recentsTemplate {
            reloadRecents()
        } else if selectedTemplate === libraryTemplate {
            reloadLibrary(refresh: true)
        } else if selectedTemplate === radioTemplate {
            if radioTemplate.sections.isEmpty {
                reloadRadio()
            }
        }
    }
}

/// Not main-actor isolated in the SDK, though CarPlay calls it on the main
/// thread — hence `assumeIsolated`.
extension CarPlayInterface: CPNowPlayingTemplateObserver {
    nonisolated func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        MainActor.assumeIsolated {
            showUpNext()
        }
    }

    /// The album, playlist or folder the queue was played from.
    nonisolated func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        MainActor.assumeIsolated {
            guard let source = LocalPlaybackService.shared.source else { return }
            pushContainer(source)
        }
    }
}
#endif
