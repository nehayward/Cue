#if os(iOS) && !targetEnvironment(macCatalyst)
import CarPlay
import Defaults
import MediaPlayer
import Observation
import SonosKit
import UIKit

/// Cue on a car's screen: four tabs and the system's Now Playing.
///
/// - **Recents** — what was last played in Cue, with Resume on top when the
///   device has a queue waiting.
/// - **Library** — each signed-in provider's playlists, recently added and
///   albums, then what's downloaded to this iPhone.
/// - **Radio** — TuneIn's and Apple Music's stations, as on the phone.
/// - **Play On** — this iPhone and the Sonos groups, to hand what's playing
///   to a speaker on arriving home (or take it back). Only while Sonos is on,
///   and the tab dropped first when a car shows fewer; Now Playing carries a
///   button for it too.
///
/// Everything plays on this device (see `CarPlayPlayback`). The car's Now
/// Playing screen is the system's, filled from the same Lock Screen card the
/// device player already publishes; this adds Up Next, the album or playlist
/// that's playing, shuffle, repeat and Play On to it.
///
/// The tabs are built once and refilled in place, following the player,
/// the route, the play history and the downloads through observation.
@MainActor
final class CarPlayInterface: NSObject {
    private let interfaceController: CPInterfaceController

    private let recentsTemplate: CPListTemplate
    private let libraryTemplate: CPListTemplate
    private let radioTemplate: CPListTemplate
    private let playOnTemplate: CPListTemplate
    private var tabBar: CPTabBarTemplate?

    /// Lists pushed from Now Playing that follow the player while they're up.
    private weak var upNextTemplate: CPListTemplate?
    private weak var pushedPlayOnTemplate: CPListTemplate?

    private var isConnected = false
    private var isLookingForSpeakers = false
    private var radioTask: Task<Void, Never>?
    private var speakersTask: Task<Void, Never>?

    /// CarPlay refuses a push past this many templates, root included.
    private static let maximumDepth = 5

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        recentsTemplate = CarPlayInterface.tab(title: "Recents", image: UIImage(systemName: "clock"))
        libraryTemplate = CarPlayInterface.tab(title: "Library", image: UIImage(systemName: "square.stack"))
        radioTemplate = CarPlayInterface.tab(title: "Radio", image: UIImage(systemName: "dot.radiowaves.left.and.right"))
        playOnTemplate = CarPlayInterface.tab(title: "Play On", image: CarPlayInterface.playOnImage)
        super.init()
    }

    private static func tab(title: String, image: UIImage?) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [])
        template.tabTitle = title
        template.tabImage = image
        return template
    }

    /// Cue's speaker-with-arrow, the route button's symbol on the phone.
    private static var playOnImage: UIImage {
        UIImage(named: "hifispeaker.arrow.forward.fill") ?? UIImage(systemName: "hifispeaker.fill") ?? UIImage()
    }

    // MARK: - Lifecycle

    func start() {
        isConnected = true
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.add(self)
        nowPlaying.upNextTitle = "Up Next"

        guard FeatureGate.shared.isAvailable(.carPlay) else {
            showUnavailable()
            return
        }

        let tabBar = CPTabBarTemplate(templates: tabs)
        tabBar.delegate = self
        self.tabBar = tabBar
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)

        // The Music app's downloads, for Library's On This iPhone: with no
        // window opened this launch, nothing else has built the index.
        AppleDownloadsIndex.shared.refreshIfNeeded()
        reloadRecents()
        reloadLibrary()
        reloadRadio()
        refreshPlayOnLists()
        updateNowPlaying()
        observe()
    }

    func stop() {
        isConnected = false
        CPNowPlayingTemplate.shared.remove(self)
        radioTask?.cancel()
        speakersTask?.cancel()
    }

    /// Recents, Library and Radio, then Play On while Sonos is on — last, so
    /// it's the one a car with room for fewer tabs leaves out.
    private var tabs: [CPTemplate] {
        var tabs: [CPTemplate] = [recentsTemplate, libraryTemplate, radioTemplate]
        if SonosService.shared.isEnabled {
            tabs.append(playOnTemplate)
        }
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
        _ = PlaybackRoute.shared.destination
        _ = SonosService.shared.isEnabled
        _ = SonosService.shared.groups
        _ = PlayHistoryService.shared.history
        _ = OnDeviceLibrary.changeToken
        // Library swaps to what's on this iPhone when the network goes.
        _ = OfflineMode.shared.isActive
    }

    private func stateChanged() {
        if let tabBar, !tabBar.templates.elementsEqual(tabs, by: { $0 === $1 }) {
            tabBar.updateTemplates(tabs)
        }
        updateNowPlaying()
        reloadRecents()
        reloadLibrary()
        refreshPlayOnLists()
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

    private func reloadRecents() {
        let player = LocalPlaybackService.shared
        let recents = CarPlayLibrary.recents()
        // The device's queue, waiting: restored from the last launch or just
        // paused. Not under a speaker route — the queue parked there is the
        // older one, and Play On is how the speaker's comes back.
        let waiting = PlaybackRoute.shared.destination == .device && !player.isPlaying ? player.nowPlaying : nil

        recentsTemplate.emptyViewTitleVariants = ["Nothing Played Yet"]
        recentsTemplate.emptyViewSubtitleVariants = ["What you play in Cue shows up here."]
        let signature = ([waiting?.id ?? ""] + recents.map(\.id)).joined(separator: "|")
        update(recentsTemplate, signature: signature) {
            var sections: [CPListSection] = []
            if let waiting {
                sections.append(CPListSection(items: [resumeRow(for: waiting)]))
            }
            if !recents.isEmpty {
                let limit = CarPlayLibrary.rowLimit - sections.count
                let rows: [CPListTemplateItem] = recents.prefix(limit).map { row(for: $0) }
                sections.append(CPListSection(items: rows, header: "Recently Played", sectionIndexTitle: nil))
            }
            return sections
        }
    }

    private func resumeRow(for item: PlayableContent) -> CPListItem {
        let row = CPListItem(text: "Resume", detailText: item.title, image: CarPlayArtwork.placeholder(for: item))
        CarPlayArtwork.load(item, into: row)
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

    private func reloadLibrary() {
        let shelves = CarPlayLibrary.shelves()
        libraryTemplate.emptyViewTitleVariants = ["Nothing to Browse"]
        libraryTemplate.emptyViewSubtitleVariants = ["Set up Apple Music, Plex, Subsonic or a Files folder in Cue on your iPhone."]
        let signature = shelves
            .map { ([$0.title] + $0.listings.map(\.title)).joined(separator: ",") }
            .joined(separator: "|")
        update(libraryTemplate, signature: signature) {
            shelves.prefix(CPListTemplate.maximumSectionCount).map { shelf -> CPListSection in
                let rows: [CPListTemplateItem] = shelf.listings.map { listingRow($0) }
                return CPListSection(items: rows, header: shelf.title, sectionIndexTitle: nil)
            }
        }
    }

    private func listingRow(_ listing: CarPlayLibrary.Listing) -> CPListItem {
        let row = CPListItem(text: listing.title, detailText: nil, image: UIImage(systemName: listing.systemImage))
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
                sections.append(CPListSection(items: [self.shuffleRow(title: "Shuffle All", playing: all)]))
            }
            if !items.isEmpty {
                let limit = CarPlayLibrary.rowLimit - sections.count
                let rows: [CPListTemplateItem] = items.prefix(limit).map { self.row(for: $0) }
                sections.append(CPListSection(items: rows))
            }
            template.updateSections(sections)
            self.updatePlayingIndicators()
        }
    }

    /// An album's or playlist's songs, with Shuffle on top. A song plays the
    /// list from there on, the way a tap in it does on the phone.
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
            let shuffle = self.shuffleRow(title: "Shuffle", playing: container)
            let rows: [CPListTemplateItem] = tracks.prefix(CarPlayLibrary.rowLimit - 1).map { self.row(for: $0, in: container) }
            template.updateSections([CPListSection(items: [shuffle]), CPListSection(items: rows)])
            self.updatePlayingIndicators()
        }
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

    // MARK: - Play On

    private func pushPlayOn() {
        let template = CPListTemplate(title: "Play On", sections: [])
        pushedPlayOnTemplate = template
        fillPlayOn(template)
        push(template)
        lookForSpeakers()
    }

    private func refreshPlayOnLists() {
        fillPlayOn(playOnTemplate)
        if let pushedPlayOnTemplate {
            fillPlayOn(pushedPlayOnTemplate)
        }
    }

    /// This iPhone, then each speaker group, with a check on where the route
    /// is. The same list as the route button's on the phone.
    private func fillPlayOn(_ template: CPListTemplate) {
        let sonos = SonosService.shared
        let destination = PlaybackRoute.shared.destination
        let groups = sonos.sorted
        let looking = isLookingForSpeakers
        let signature = ([String(describing: destination), String(looking)] + groups.map { group in
            "\(group.coordinatorID),\(group.nameWithCount),\(nowPlayingLine(of: group) ?? "")"
        }).joined(separator: "|")

        update(template, signature: signature) {
            let device = destinationRow(
                title: "This iPhone",
                detail: nil,
                image: UIImage(systemName: "iphone"),
                isCurrent: destination == .device,
                target: .device
            )
            let speakers: [CPListTemplateItem]
            if groups.isEmpty {
                let note = CPListItem(
                    text: looking ? "Looking for Speakers…" : "No Speakers Found",
                    detailText: looking ? nil : "Speakers on your home network show up here."
                )
                note.handler = { [weak self] _, completion in
                    MainActor.assumeIsolated {
                        self?.lookForSpeakers()
                        completion()
                    }
                }
                speakers = [note]
            } else {
                speakers = groups.map { group -> CPListTemplateItem in
                    destinationRow(
                        title: group.nameWithCount,
                        detail: nowPlayingLine(of: group),
                        image: UIImage(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill"),
                        isCurrent: destination.groupID == group.coordinatorID,
                        target: .group(group.coordinatorID)
                    )
                }
            }
            return [
                CPListSection(items: [device]),
                CPListSection(items: speakers, header: "Speakers", sectionIndexTitle: nil),
            ]
        }
    }

    private func nowPlayingLine(of group: GroupRoom) -> String? {
        let room = group.coordinatorRoom
        guard room.isPlaying, !room.track.song.isEmpty else { return nil }
        return room.track.song
    }

    private func destinationRow(title: String, detail: String?, image: UIImage?, isCurrent: Bool, target: PlayDestination) -> CPListItem {
        let row = CPListItem(
            text: title,
            detailText: detail,
            image: image,
            accessoryImage: isCurrent ? UIImage(systemName: "checkmark") : nil,
            accessoryType: .none
        )
        row.handler = { [weak self] _, completion in
            MainActor.assumeIsolated {
                self?.playOn(target)
                completion()
            }
        }
        return row
    }

    /// Hands what's playing over to `target`. There's no prompt in the car:
    /// Ask moves it, which is what arriving home with music on wants; only
    /// Don't Move (Settings › Playback) leaves it where it is.
    private func playOn(_ target: PlayDestination) {
        let route = PlaybackRoute.shared
        guard target != route.destination else { return }
        if target == .device, !FeatureGate.shared.isAvailable(.onDevicePlayback) {
            showAlert("Playing on This iPhone Needs Cue Super")
            return
        }
        if let id = target.groupID, !SonosService.shared.groups.contains(where: { $0.coordinatorID == id }) {
            showAlert("That speaker isn't available right now")
            return
        }
        route.switchTo(target, carrying: QueueTransferPreference.current != .never)
        refreshPlayOnLists()
    }

    /// One load of the speakers, not monitoring: the phone's monitoring is
    /// stopped while its screen is off, which in a car is all the time. The
    /// hand-off's first read is taken at the same time, as the phone's Play
    /// On menu does.
    private func lookForSpeakers() {
        let sonos = SonosService.shared
        guard sonos.isEnabled, speakersTask == nil else { return }
        isLookingForSpeakers = true
        refreshPlayOnLists()
        speakersTask = Task { [weak self] in
            try? await sonos.updateGroups()
            PlaybackRoute.shared.prefetchTargets()
            guard let self else { return }
            self.isLookingForSpeakers = false
            self.speakersTask = nil
            self.refreshPlayOnLists()
        }
    }

    // MARK: - Now Playing

    /// Up Next and the album button while the device has a queue; shuffle and
    /// repeat for a queue of songs (a station has neither); Play On while
    /// Sonos is on.
    private func updateNowPlaying() {
        let player = LocalPlaybackService.shared
        let onDevice = PlaybackRoute.shared.destination == .device && player.isActive
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.isUpNextButtonEnabled = onDevice && !player.upNext.isEmpty
        nowPlaying.isAlbumArtistButtonEnabled = onDevice && player.source.map { player.canPlayContainerLocally($0) } == true

        var buttons: [CPNowPlayingButton] = []
        if onDevice, !player.isPlayingStation {
            let shuffle = CPNowPlayingShuffleButton { _ in
                MainActor.assumeIsolated {
                    let player = LocalPlaybackService.shared
                    player.setShuffle(!player.isShuffled)
                }
            }
            shuffle.isSelected = player.isShuffled
            let repeatButton = CPNowPlayingRepeatButton { _ in
                MainActor.assumeIsolated {
                    let player = LocalPlaybackService.shared
                    player.setRepeatMode(player.repeatMode.next)
                }
            }
            repeatButton.isSelected = player.repeatMode != .off
            buttons += [shuffle, repeatButton]

            // What the two buttons draw their state from.
            let commands = MPRemoteCommandCenter.shared()
            commands.changeShuffleModeCommand.currentShuffleType = player.isShuffled ? .items : .off
            commands.changeRepeatModeCommand.currentRepeatType = switch player.repeatMode {
            case .off: .off
            case .all: .all
            case .one: .one
            }
        }
        if SonosService.shared.isEnabled {
            buttons.append(CPNowPlayingImageButton(image: Self.playOnImage) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.pushPlayOn()
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
        let opens = !LocalPlaybackService.shared.canPlayLocally(content)
        let row = CPListItem(text: content.title, detailText: detail(for: content), image: CarPlayArtwork.placeholder(for: content))
        CarPlayArtwork.load(content, into: row)
        if opens {
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
                if opens {
                    self.pushContainer(content)
                    completion()
                } else if let container {
                    self.perform(completion: completion) {
                        try await CarPlayPlayback.play(content, in: container)
                    }
                } else {
                    self.perform(completion: completion) {
                        try await CarPlayPlayback.play([content])
                    }
                }
            }
        }
        return row
    }

    private func shuffleRow(title: String, playing container: PlayableContent) -> CPListItem {
        let row = CPListItem(text: title, detailText: nil, image: UIImage(systemName: "shuffle"))
        row.handler = { [weak self] _, completion in
            MainActor.assumeIsolated {
                guard let self else {
                    completion()
                    return
                }
                self.perform(completion: completion) {
                    try await CarPlayPlayback.play([container], shuffle: true)
                }
            }
        }
        return row
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
    /// the phone, a provider switched off — so they're re-read on the way
    /// in. Radio is loaded once, and again if it came up empty. Play On
    /// looks for speakers.
    func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
        if selectedTemplate === recentsTemplate {
            reloadRecents()
        } else if selectedTemplate === libraryTemplate {
            reloadLibrary()
        } else if selectedTemplate === radioTemplate {
            if radioTemplate.sections.isEmpty {
                reloadRadio()
            }
        } else if selectedTemplate === playOnTemplate {
            lookForSpeakers()
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
