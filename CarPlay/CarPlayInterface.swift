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
/// - **Library** — the signed-in providers' playlists, with Recently Added
///   and Albums pinned above them.
/// - **Downloads** — what's on this iPhone, which plays with no signal:
///   Shuffle All, Albums, Artists and Songs, and the newest albums.
/// - **Radio** — TuneIn's and Apple Music's stations, as on the phone.
///
/// Everything plays on this device (see `CarPlayPlayback`); speakers have
/// no place in a car, so nothing here offers one. The car's Now Playing
/// screen is the system's, filled from the card the device player publishes
/// (see `LocalNowPlayingPresenter`); this adds Up Next, the album or
/// playlist that's playing, shuffle and repeat to it.
///
/// The newest plays and downloads are iOS 26 card rows, and Play, Shuffle
/// and the Downloads tab's ways in are pinned above their lists. From iOS
/// 27 an album or playlist opens under a details header with its cover, and
/// the system's MiniPlayer shows what's playing without any work here.
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

    private var isConnected = false
    private var radioTask: Task<Void, Never>?
    /// The Library tab's playlists while they load; nil once they're in.
    private var libraryTask: Task<Void, Never>?
    /// The providers the Library tab was last filled from. The player's
    /// changes, which come often, don't fetch the playlists again; a
    /// provider coming or going, or the tab being picked, does.
    private var libraryServices: [MediaSearchService]?
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
    /// app does. Rows carry their content's id in `userInfo` for this.
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
            }
        }
    }

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

    /// The signed-in providers' playlists, each under its name when there's
    /// more than one, with Recently Added and Albums pinned above them. The
    /// buttons are up at once; the playlists fill in when the providers
    /// answer, and again when the tab is picked (`refresh`).
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
        libraryServices = services
        libraryTask?.cancel()
        libraryTask = nil

        guard !services.isEmpty else {
            libraryTemplate.showsSpinnerWhileEmpty = false
            libraryTemplate.headerGridButtons = nil
            update(libraryTemplate, signature: "") { [] }
            return
        }
        let collections = CarPlayLibrary.libraryCollections(for: services)
        // An empty tab fills in as each provider answers. One already
        // filled keeps its rows until they've all answered, so a refresh
        // doesn't drop the slower providers' playlists for a moment.
        let fillsAsTheyCome = libraryTemplate.sections.isEmpty
        if fillsAsTheyCome {
            libraryTemplate.showsSpinnerWhileEmpty = true
            libraryTemplate.headerGridButtons = collectionButtons(collections)
        }
        libraryTask = Task { [weak self] in
            let shelves = await CarPlayLibrary.shelves(.playlists, from: services) { soFar in
                guard fillsAsTheyCome else { return }
                self?.fillLibrary(playlists: soFar, collections: collections)
            }
            guard let self, !Task.isCancelled else { return }
            self.libraryTask = nil
            self.fillLibrary(playlists: shelves, collections: collections)
        }
    }

    /// With no playlists, the buttons' collections become the list's rows,
    /// so the tab never stands empty while there's something to browse.
    private func fillLibrary(playlists: [CarPlayLibrary.Shelf], collections: [ProviderCollection]) {
        libraryTemplate.showsSpinnerWhileEmpty = false
        let pinned = playlists.isEmpty ? [] : collectionButtons(collections)
        // A car with room for fewer buttons still gets every way in.
        let unpinned = collections.dropFirst(pinned.count)
        let ways = collections.prefix(pinned.count).map(\.rawValue) + ["/"] + unpinned.map(\.rawValue)
        let signature = ([ways.joined(separator: ",")] + playlists.map { ([$0.title] + $0.items.map(\.id)).joined(separator: ",") })
            .joined(separator: "|")
        guard (libraryTemplate.userInfo as? String) != signature else { return }
        libraryTemplate.userInfo = signature
        libraryTemplate.headerGridButtons = pinned.isEmpty ? nil : pinned

        var sections: [CPListSection] = []
        if !unpinned.isEmpty {
            sections.append(CPListSection(items: unpinned.map { collectionRow($0) }))
        }
        sections += shelfSections(playlists)
        libraryTemplate.updateSections(Array(sections.prefix(CPListTemplate.maximumSectionCount)))
    }

    /// As many of the Library tab's buttons as the car pins above a list.
    private func collectionButtons(_ collections: [ProviderCollection]) -> [CPGridButton] {
        collections.prefix(CPListTemplate.maximumHeaderGridButtonCount).map { collection in
            gridButton(titleVariants: [collection.title], systemImage: collection.systemImage) { [weak self] in
                self?.pushCollection(collection)
            }
        }
    }

    private func collectionRow(_ collection: ProviderCollection) -> CPListItem {
        let row = CPListItem(text: collection.title, detailText: nil, image: CarPlayArtwork.symbol(collection.systemImage))
        row.accessoryType = .disclosureIndicator
        row.handler = { [weak self] _, completion in
            MainActor.assumeIsolated {
                self?.pushCollection(collection)
                completion()
            }
        }
        return row
    }

    /// Recently Added or Albums from every provider the Library tab browses.
    /// Opens at once on a spinner, as a listing does, and fills in as each
    /// provider answers.
    private func pushCollection(_ collection: ProviderCollection) {
        let services = CarPlayLibrary.libraryServices()
        let template = CPListTemplate(title: collection.title, sections: [])
        template.showsSpinnerWhileEmpty = true
        push(template)
        Task { [weak self, weak template] in
            await CarPlayLibrary.shelves(collection, from: services) { shelves in
                guard let self, let template else { return }
                template.updateSections(self.shelfSections(shelves))
                self.updatePlayingIndicators()
            }
            // Every shelf went up as it arrived; all that's left is the
            // spinner, and what to say when nothing came.
            guard let template else { return }
            template.showsSpinnerWhileEmpty = false
            template.emptyViewTitleVariants = ["Nothing Here"]
            template.emptyViewSubtitleVariants = ["Nothing here can play on this iPhone."]
        }
    }

    /// A section per provider, under its name when there's more than one.
    /// The car's row limit is shared out, so one long library can't crowd
    /// the others off the list.
    private func shelfSections(_ shelves: [CarPlayLibrary.Shelf]) -> [CPListSection] {
        let shown = Array(shelves.prefix(CPListTemplate.maximumSectionCount))
        let counts = Self.share(CarPlayLibrary.rowLimit, among: shown.map(\.items.count))
        let named = shown.count > 1
        return zip(shown, counts).map { (shelf, count) -> CPListSection in
            let rows: [CPListTemplateItem] = shelf.items.prefix(count).map { row(for: $0) }
            return CPListSection(items: rows, header: named ? shelf.title : nil, sectionIndexTitle: nil)
        }
    }

    /// Shares `limit` rows among lists of `counts` rows: a short list keeps
    /// all of its rows, and the longer ones split what's left evenly.
    private static func share(_ limit: Int, among counts: [Int]) -> [Int] {
        var shares = Array(repeating: 0, count: counts.count)
        var remaining = limit
        var left = counts.count
        for index in counts.indices.sorted(by: { counts[$0] < counts[$1] }) {
            shares[index] = min(counts[index], remaining / left)
            remaining -= shares[index]
            left -= 1
        }
        return shares
    }

    private func listingRow(_ listing: CarPlayLibrary.Listing) -> CPListItem {
        let row = CPListItem(text: listing.title, detailText: listing.detail, image: CarPlayArtwork.symbol(listing.systemImage))
        row.accessoryType = .disclosureIndicator
        row.handler = { [weak self] _, completion in
            MainActor.assumeIsolated {
                self?.pushListing(listing)
                completion()
            }
        }
        return row
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
                template.headerGridButtons = self.playButtons(
                    play: { try await CarPlayPlayback.play(items, startingAt: 0) },
                    shuffle: { try await CarPlayPlayback.play([all], shuffle: true) }
                )
            }
            if !items.isEmpty {
                let limit = CarPlayLibrary.rowLimit
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
            if #available(iOS 27.0, *) {
                self.showDetailsHeader(on: template, for: container, play: play, shuffle: shuffle)
            } else {
                template.headerGridButtons = self.playButtons(play: play, shuffle: shuffle)
            }
            let rows: [CPListTemplateItem] = tracks.prefix(CarPlayLibrary.rowLimit).map { self.row(for: $0, in: container) }
            template.updateSections([CPListSection(items: rows)])
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

    /// Shuffle All, Albums, Artists and Songs pinned on top, then the albums
    /// that arrived last as cards. Refilled only when what's on the device
    /// has changed.
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
            downloadsTemplate.headerGridButtons = nil
            downloadsTemplate.updateSections([])
            return
        }

        let all = CarPlayLibrary.allDownloads
        let listings = CarPlayLibrary.downloadListings()
        let shuffle = gridButton(titleVariants: ["Shuffle All", "Shuffle"], systemImage: "shuffle") { [weak self] in
            self?.perform(completion: {}) {
                try await CarPlayPlayback.play([all], shuffle: true)
            }
        }
        let browse = listings.map { listing in
            gridButton(titleVariants: [listing.title], systemImage: listing.systemImage) { [weak self] in
                self?.pushListing(listing)
            }
        }
        let pinned = min(1 + browse.count, CPListTemplate.maximumHeaderGridButtonCount)
        downloadsTemplate.headerGridButtons = Array(([shuffle] + browse).prefix(pinned))

        var sections: [CPListSection] = []
        let recent = CarPlayLibrary.recentlyDownloaded()
        if !recent.isEmpty {
            let cards = cardRow(title: "Recently Downloaded", items: recent) { [weak self] in
                self?.pushListing(CarPlayLibrary.recentlyDownloadedListing)
            }
            sections.append(CPListSection(items: [cards]))
        }
        // A car with room for fewer buttons still gets every way in.
        let unpinned = listings.dropFirst(max(0, pinned - 1))
        if !unpinned.isEmpty {
            sections.append(CPListSection(items: unpinned.map { listingRow($0) }))
        }
        downloadsTemplate.updateSections(sections)
    }

    // MARK: - Radio

    /// Stations per section, so one long list can't push the rest off a
    /// car's screen.
    private static let stationsPerSection = 20

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
                sections.prefix(CPListTemplate.maximumSectionCount).map { section -> CPListSection in
                    let rows: [CPListTemplateItem] = section.stations.prefix(Self.stationsPerSection).map { self.row(for: $0) }
                    return CPListSection(items: rows, header: section.title, sectionIndexTitle: nil)
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

    /// Up Next and the album button while the device has a queue; shuffle and
    /// repeat for a queue of songs (a station has neither).
    private func updateNowPlaying() {
        let player = LocalPlaybackService.shared
        let onDevice = PlaybackRoute.shared.destination == .device && player.isActive
        let nowPlaying = CPNowPlayingTemplate.shared
        // Up whenever there's a queue of songs, on its last song too, as
        // the Music app's is. A station alone has no queue to show.
        nowPlaying.isUpNextButtonEnabled = onDevice && (!player.isPlayingStation || !player.upNext.isEmpty)
        nowPlaying.isAlbumArtistButtonEnabled = onDevice && player.source.map { player.canPlayContainerLocally($0) } == true

        var buttons: [CPNowPlayingButton] = []
        if onDevice, !player.isPlayingStation {
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
        nowPlaying.updateNowPlayingButtons(buttons)
    }

    private func showUpNext() {
        let template = CPListTemplate(title: "Up Next", sections: [])
        template.emptyViewTitleVariants = ["Nothing Up Next"]
        upNextTemplate = template
        fillUpNext(template)
        push(template)
    }

    private func fillUpNext(_ template: CPListTemplate) {
        let upNext = Array(LocalPlaybackService.shared.upNext.prefix(CarPlayLibrary.rowLimit))
        update(template, signature: upNext.map(\.id).joined(separator: "|")) {
            guard !upNext.isEmpty else { return [] }
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
            return [CPListSection(items: rows)]
        }
    }

    /// Plays an Up Next row and goes back to Now Playing. Looked up again
    /// rather than kept as an index: the queue can have moved since the
    /// list was drawn.
    private func jump(to content: PlayableContent) {
        let player = LocalPlaybackService.shared
        let upcoming = player.queue.indices.dropFirst(player.currentIndex + 1)
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
        for (element, item) in zip(elements, items) {
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
        return row
    }

    /// Play and Shuffle, pinned above a list of songs.
    private func playButtons(
        play: @escaping @MainActor () async throws -> Void,
        shuffle: @escaping @MainActor () async throws -> Void
    ) -> [CPGridButton] {
        [
            gridButton(titleVariants: ["Play"], systemImage: "play.fill") { [weak self] in
                self?.perform(completion: {}, play)
            },
            gridButton(titleVariants: ["Shuffle"], systemImage: "shuffle") { [weak self] in
                self?.perform(completion: {}, shuffle)
            },
        ]
    }

    /// A button pinned above a list (`headerGridButtons`). Plain system
    /// symbols only: custom images don't draw there on iOS 27
    /// (FB24806621), and a symbol recoloured for the car's look
    /// (`CarPlayArtwork.symbol`) counts as one: the buttons came up as
    /// bare titles.
    private func gridButton(titleVariants: [String], systemImage: String, _ action: @escaping @MainActor () -> Void) -> CPGridButton {
        let image = UIImage(systemName: systemImage) ?? UIImage()
        return CPGridButton(titleVariants: titleVariants, image: image) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
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
