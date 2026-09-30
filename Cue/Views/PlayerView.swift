import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI
import VibesDS

/// The player: full screen, opened from the tab bar accessory, showing
/// whatever the route points at — this device, or the Sonos group chosen
/// in the route button. One screen for both, so switching the route never
/// swaps the player out from under the user; the sections just read from
/// `LocalPlaybackService` or from the group.
///
/// The navigation bar names the device or the group, with the sleep timer,
/// the like button and the menu beside it; below it the artwork, the album line,
/// the title and the artist (each opening its detail), the scrubber with
/// the audio-quality badge, the transport, the volume row with its
/// steppers, and the glass bar: the route picker, on a speaker the group
/// button with its press-and-hold regroup menu, search, browse, and the
/// queue at the trailing edge. A speaker's sections are the same views
/// `LargePlayerView` draws, so the two can't drift.
struct PlayerView: View {
    @AppStorage(AppStorageKeys.showArtworkOnly) private var showArtworkOnly: Bool = false
    /// The same key the main window's panel uses, so showing the queue here
    /// shows it there too rather than the two disagreeing.
    @AppStorage(AppStorageKeys.queueInspectorVisible) private var showQueue: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The cover's own router. The main window's sheets hang off the tab
    /// content underneath this cover, so anything routed there would come
    /// up behind it; everything in here presents on this one instead.
    @State private var router = Router()
    @State private var isArtworkVisible: Bool = true
    @State private var showSleepTimerCancelConfirmation: Bool = false
    /// The Sonos artwork's crossfade window — see `GroupMediaControlsView`,
    /// which closes it around a skip so a deliberate change snaps.
    @State private var shouldFade: Bool = false

    private var playback: LocalPlaybackService { .shared }
    private var sonosService: SonosService { .shared }
    private var route: PlaybackRoute { .shared }

    /// The group the route points at, resolved on every read: a topology
    /// refresh replaces every `GroupRoom`, so nothing here holds one.
    private var group: GroupRoom? { route.group }

    /// iPad at a regular width: the queue toggle is in the navigation bar.
    private var showsQueueToolbarButton: Bool {
#if targetEnvironment(macCatalyst)
        false
#else
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
#endif
    }

    /// Matches `LargePlayerView`: the wide layout is for anything that isn't a
    /// phone, Catalyst included.
    private var isMacCatalystOrPad: Bool {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return true
        }
#if targetEnvironment(macCatalyst)
        return true
#else
        return false
#endif
    }

    /// `shouldFade` covers skips made from this screen's own transport; the
    /// ⌘← / ⌘→ commands can't reach that state, so they open an equivalent
    /// window on the main router.
    private var artworkShouldFade: Bool {
        shouldFade && !Router.main.isSkippingTrack
    }

    /// Live Transcription can run here: a station is playing, on this device
    /// or the speaker the route points at.
    private var canTranscribe: Bool {
        LiveTranscriptionService.isSupported && LiveTranscriptionService.isStationPlaying
    }

    /// Live Transcription is on, in the artwork's place.
    private var showsTranscription: Bool {
        LiveTranscriptionService.shared.isEnabled && canTranscribe
    }

    /// The bar's title: this device, or the group's name.
    private var deviceName: String { UIDevice.current.name }

    var body: some View {
        // The stack sits inside the queue panel, so its bar spans the player
        // column only, and the backdrop is drawn behind both from outside.
        // An earlier stack here lost the zoom out of the mini player; if it
        // goes again, that's where to look.
        NavigationStack {
            VStack(alignment: .center) {
                if let group {
                    groupContent(group)
                } else if let item = playback.nowPlayingDisplay {
                    // The display item, not the queue row: a station reads as
                    // the song on air here.
                    deviceContent(item)
                } else {
                    Spacer()
                    ContentUnavailableView("Nothing Playing", systemImage: "iphone.radiowaves.left.and.right")
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.interactiveSpring, value: showArtworkOnly)
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .safeAreaPadding(.bottom)
            .ignoresSafeArea(.keyboard)
            .toolbar { toolbarContent }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .modifier(ClearNavigationBackground { backdrop })
        }
        // Presented from in here rather than the main window: its sheets
        // hang off the tab content underneath this cover and would come up
        // behind it.
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
        .withAlert()
        // The same trailing panel the main window uses where there's room —
        // it shows and hides in place, and the artwork reflows around it —
        // and a half-height sheet on a phone, where a side panel would only
        // squeeze both halves. `QueueNextUpView` follows the route too.
        .queuePanel(isPresented: $showQueue) {
            QueueNextUpView()
        }
        .background { backdrop }
        // The speaker's socket, sleep timer, play mode and hardware volume
        // while a group is on screen; a drop on the screen plays wherever
        // the route points.
        .modifier(PlayerSessionModifier(coordinatorID: group?.coordinatorID, shouldFade: $shouldFade))
        .fontDesign(.rounded)
        .environment(router)
        .withEnvironments()
    }

    /// The blurred artwork behind the whole cover, queue panel included.
    ///
    /// Clipped to the cover: both backdrops are scaled up and blurred past
    /// their edges, and the Mac's plain slide-down cover doesn't clip its
    /// content the way the zoom does. Unclipped, the overhang above the
    /// cover's top edge was left sitting over the bottom of the window —
    /// covering the mini player — until the dismiss finished.
    ///
    /// `ignoresSafeArea` goes outside the clip so the clip is laid out at the
    /// full cover, title bar included; clipped at the safe area instead, the
    /// backdrop stopped short of the window's top edge.
    private var backdrop: some View {
        VStack(spacing: 0) {
            if let group {
                GroupPlayerBackgroundView(group: group, shouldFade: artworkShouldFade)
            } else {
                PlayerBackgroundView(content: playback.nowPlayingDisplay)
            }
        }
        .clipped()
        .ignoresSafeArea()
    }

    // MARK: - This device

    @ViewBuilder
    private func deviceContent(_ item: PlayableContent) -> some View {
        // Live Transcription takes the artwork's place, in the same frame,
        // so the controls below don't move when it's switched.
        Group {
            if showsTranscription {
                LiveTranscriptionView()
                    .transition(.opacity)
            } else {
                ContentArtworkView(content: item, showMusicSource: true, preferredSize: 600, cornerRadius: 8, isDraggable: true)
                    .shadow(radius: 2)
                    .transition(.opacity)
            }
        }
            .padding(.bottom, showArtworkOnly ? 0 : 12)
            .frame(minWidth: 0, maxWidth: showArtworkOnly ? .infinity : (isMacCatalystOrPad ? 800 : 500), minHeight: 0, maxHeight: showArtworkOnly ? .infinity : (isMacCatalystOrPad ? .infinity : 400))
            .padding(.top, showArtworkOnly ? 100 : nil)
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.size.height >= 100
            } action: { isArtworkVisible = $0 }
            .opacity(isArtworkVisible ? 1 : 0)
            .animation(.interactiveSpring, value: isArtworkVisible)

        // Where the queue was played from, in the slot the speaker's
        // container line takes — the album when there is no origin, and the
        // station's name when a station is playing. Fixed height so the
        // layout doesn't shift between tracks that have one and tracks that
        // don't.
        LocalAlbumButton(
            item: item,
            source: playback.source,
            stationTitle: item.content.type.isRadio ? (playback.nowPlaying?.title ?? "") : nil
        )
        .frame(height: 12)
        // While a station plays, a tap opens the song on air once Apple
        // Music has it — named by the station or by Shazam.
        LocalSongTitleButton(item: item, target: playback.onAirMatch)
        LocalArtistButton(item: item, target: playback.onAirMatch, showArtworkOnly: showArtworkOnly)

        if !showArtworkOnly {
            VStack {
                LocalPlaybackScrubber()
                LocalMediaControlsView()
            }
            .geometryGroup()
            .transition(.opacity.combined(with: .push(from: .bottom)))

            VStack {
                LocalVolumeControlView()
                    .padding(.bottom, 20)
                    .padding(.horizontal, -12)
                    .frame(maxWidth: 500)

                PlayerBottomToolbarView(group: nil, showQueue: $showQueue)
            }
            .transition(.opacity)
        }
    }

    // MARK: - A speaker

    /// The group's sections, as `LargePlayerView` lays them out: TV mode
    /// gets the TV glyph and its controls in place of artwork and transport.
    @ViewBuilder
    private func groupContent(_ group: GroupRoom) -> some View {
        if group.TVMode {
            VStack {
                Spacer()
                Image(systemName: "tv")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolRenderingMode(.hierarchical)
                    .opacity(0.2)
                    .overlay {
                        if group.isMuted {
                            Image(systemName: "speaker.slash.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.primary)
                                .bold()
                                .containerRelativeFrame(.horizontal) { size, _ in
                                    size * 0.25
                                }
                                .frame(maxWidth: isMacCatalystOrPad ? 600 : 400, maxHeight: 400)
                                .background {
                                    RoundedRectangle(cornerRadius: 8)
                                        .foregroundStyle(.ultraThinMaterial)
                                }
                                .transition(.opacity)
                                .tint(.primary)
                        }
                    }
                    .animation(.spring, value: group.isMuted)
                    .frame(maxWidth: 400, maxHeight: 400)
                GroupTVModeView(group: group)
                Spacer()
            }
            .transition(.opacity)
        } else {
            // Live Transcription takes the artwork's place here too.
            Group {
                if showsTranscription {
                    LiveTranscriptionView()
                        .transition(.opacity)
                } else {
                    ArtworkView(group: group, isDraggable: true, showBadge: true, shouldFade: artworkShouldFade)
                        .transition(.opacity)
                }
            }
                .padding(.bottom, showArtworkOnly ? 0 : 12)
                .frame(minWidth: 0, maxWidth: showArtworkOnly ? .infinity : (isMacCatalystOrPad ? 800 : 500), minHeight: 0, maxHeight: showArtworkOnly ? .infinity : (isMacCatalystOrPad ? .infinity : 400))
                .padding(.top, showArtworkOnly ? 100 : nil)
                .onGeometryChange(for: Bool.self) { proxy in
                    proxy.size.height >= 100
                } action: { isArtworkVisible = $0 }
                .opacity(isArtworkVisible ? 1 : 0)
                .animation(.interactiveSpring, value: isArtworkVisible)

            VStack {
                if group.coordinatorRoom.container != nil {
                    TrackContainerView(group: group)
                        .transition(.opacity)
                        .contentTransition(.identity)
                } else {
                    Text(group.coordinatorRoom.radioStation ?? "")
                        .font(.caption.smallCaps())
                        .foregroundStyle(.secondary)
                        .lineLimit(1, reservesSpace: true)
                        .contentTransition(.identity)
                }
            }
            .animation(.default, value: group.coordinatorRoom.container != nil)
            .frame(height: 12)
            GroupSongTitleButton(group: group)
            GroupArtistButton(group: group, showArtworkOnly: showArtworkOnly)

            if !showArtworkOnly {
                VStack {
                    GroupPlaybackScrubber(group: group)
                    GroupMediaControlsView(group: group, shouldFade: $shouldFade)
                }
                .geometryGroup()
                .transition(.opacity.combined(with: .push(from: .bottom)))
            }
        }

        if !showArtworkOnly || group.TVMode {
            VStack {
                VolumeControlView(group: group)
                    .padding(.bottom, 20)
                    .padding(.horizontal, -12)
                    .frame(maxWidth: 500)

                PlayerBottomToolbarView(group: group, showQueue: $showQueue)
            }
            .transition(.opacity)
        }
    }

    // MARK: - Toolbar

    /// The device or the group in the middle with its service or battery
    /// under it (and a close chevron leading on the Mac), and trailing the sleep timer, the
    /// like button and the menu — up here on every size, so the bar below
    /// is only ever about where to go.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
#if targetEnvironment(macCatalyst)
        // Only on the Mac: elsewhere the zoom dismisses on a downward drag,
        // but the Mac's plain cover has no gesture to close it.
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
            }
            .tint(.primary)
            .help("Close")
        }
#endif

        ToolbarItem(placement: .principal) {
            title
        }

        if let chip = sleepTimerChip {
#if !os(visionOS)
            if #available(iOS 26.0, *) {
                // Its own capsule, apart from the buttons beside it.
                ToolbarItem(placement: .topBarTrailing) { chip }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            } else {
                ToolbarItem(placement: .topBarTrailing) { chip }
            }
#else
            ToolbarItem(placement: .topBarTrailing) { chip }
#endif
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if canTranscribe {
                LiveTranscriptionButton()
                    .tint(.primary)
            }
            if let group {
                LikeButtonView(group: group)
                MenuInfoView(group: group, showArtworkOnly: $showArtworkOnly)
                    .tint(.primary)
                    .modifier(GroupRefreshOnForegroundModifier())
            } else if let item = playback.nowPlaying {
                // The song on air, while a station plays and Apple
                // Music has it.
                if let song = playback.onAirMatch {
                    LikeButtonView(content: song)
                        .id(song.content.id)
                } else if item.content.service.supportsFavoriteTrack {
                    LikeButtonView(content: item)
                }
                LocalPlayerMenuView(item: item, showArtworkOnly: $showArtworkOnly)
                    .tint(.primary)
            }
            // iPad's queue toggle, up here with the other controls rather
            // than in the glass row under the volume, where it reflowed with
            // the artwork as the panel slid in. The phone keeps it in its
            // bar (the queue is a sheet there); the Mac has the window
            // toolbar's.
            if showsQueueToolbarButton {
                Button {
                    HapticManager.shared.fireHaptic(.selection)
                    withAnimation(.snappy) {
                        showQueue.toggle()
                    }
                } label: {
                    Label(showQueue ? "Hide Up Next" : "Show Up Next", systemImage: "list.bullet")
                        .labelStyle(.iconOnly)
                }
                .tint(showQueue ? Color("Accent") : .primary)
                .accessibilityAddTraits(showQueue ? .isSelected : [])
            }
        }
    }

    /// The device or the group, with its lowest battery or the service the
    /// track is coming from under it.
    private var title: some View {
        VStack(spacing: 0) {
            Text(group?.nameWithCount ?? deviceName)
                .bold()
                .fontDesign(.rounded)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .contentTransition(.identity)
            if let group {
                // The lowest battery in the group, for a Roam or Move:
                // the one at risk first.
                if let battery = group.lowestBattery {
                    Text("\(Int(battery.percentage.rounded()))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else if let item = playback.nowPlaying {
                // Where a speaker shows a battery, this shows the
                // service the track is coming from.
                Text(item.content.service.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .contentTransition(.identity)
            }
        }
    }

    /// The sleep timer chip for whatever is on screen, or `nil` while no
    /// timer is set.
    private var sleepTimerChip: AnyView? {
        if let group {
            guard let date = group.coordinatorRoom.sleepTimer, date > Date.now else { return nil }
            return AnyView(sleepTimerChip(on: group.coordinatorRoom.name) {
                Text(date, style: .timer)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.spring, value: date)
                    .monospacedDigit()
                    .bold()
            } cancel: {
                Task { await sonosService.stopSleepTimer(group: group) }
            })
        }
        guard playback.nowPlaying != nil else { return nil }
        if let date = playback.sleepTimerEndDate, date > Date.now {
            return AnyView(sleepTimerChip(on: deviceName) {
                Text(date, style: .timer)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.spring, value: date)
                    .monospacedDigit()
                    .bold()
            } cancel: {
                playback.cancelSleepTimer()
            })
        }
        if playback.sleepsAtEndOfTrack {
            return AnyView(sleepTimerChip(on: deviceName) {
                Text("End of Song")
                    .bold()
            } cancel: {
                playback.cancelSleepTimer()
            })
        }
        return nil
    }

    /// The sleep timer chip: the moon, whatever `detail` says about when,
    /// and a confirmation to call it off on `target`.
    private func sleepTimerChip<Detail: View>(on target: String, @ViewBuilder detail: () -> Detail, cancel: @escaping () -> Void) -> some View {
        Button {
            showSleepTimerCancelConfirmation = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.primary.gradient, .indigo)
                detail()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .capsuleGlass()
        .accessibilityLabel("Sleep Timer")
        .confirmationDialog(
            "Cancel Sleep Timer",
            isPresented: $showSleepTimerCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Sleep Timer", role: .destructive, action: cancel)
            Button("Keep Timer", role: .cancel) { }
        } message: {
            Text("Stop the sleep timer on \(target)?")
        }
    }
}

// MARK: - Navigation background

/// Lets the backdrop drawn behind the whole cover show through the
/// navigation stack. Before iOS 18 the stack's background can't be cleared,
/// so the backdrop is drawn again inside it.
private struct ClearNavigationBackground<Backdrop: View>: ViewModifier {
    @ViewBuilder var backdrop: () -> Backdrop

    func body(content: Content) -> some View {
        if #available(iOS 18.0, visionOS 2.0, *) {
            content
                .containerBackground(.clear, for: .navigation)
        } else {
            content
                .background { backdrop() }
        }
    }
}

// MARK: - Session

/// What a speaker on screen needs kept alive — its metadata socket, the
/// crossfade flag, sleep timer and play mode reads, the scene-phase sync,
/// hardware volume — the same set `LargePlayerView` runs, and where a drop
/// on the screen goes. Nothing but the drop target for the device.
private struct PlayerSessionModifier: ViewModifier {
    let coordinatorID: String?
    @Binding var shouldFade: Bool

    private var sonosService: SonosService { .shared }

    /// Resolved fresh on every read, and again inside each task, so a
    /// topology refresh can't leave an orphaned instance behind.
    private var group: GroupRoom? {
        coordinatorID.flatMap { id in sonosService.groups.first { $0.coordinatorID == id } }
    }

    func body(content: Content) -> some View {
        if let group {
            content
                .dropDestinationPlay(on: group)
                .hardwareVolumeControl(group: group)
                .modifier(GroupScenePhaseSyncModifier(coordinatorID: group.coordinatorID))
                .task(id: group.coordinatorID) {
                    guard let group = self.group else { return }
                    // Re-points the `.viewing` listener; the registry closes
                    // the previous group's socket unless another listener
                    // still needs it.
                    await sonosService.getTrackAudioInformation(ip: group.ip, playerID: group.coordinatorID, groupID: group.id)
                    group.isCrossfaded = await sonosService.isCrossfaded(for: group)
                    await sonosService.getSleepTimer(group: group)
                }
                .task(id: group.coordinatorID) {
                    guard let group = self.group else { return }
                    sonosService.selectedGroup = group
                    try? await sonosService.updateTrackInformation(for: [group])
                }
                .task(id: group.coordinatorID) {
                    guard let group = self.group else { return }
                    let awaitedPlayMode = await sonosService.playMode(ip: group.ip)
                    if group.playMode != awaitedPlayMode {
                        group.playMode = awaitedPlayMode
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                    shouldFade = true
                }
                .onChange(of: group.coordinatorID) {
                    shouldFade = false
                }
#if !targetEnvironment(macCatalyst)
                .onDisappear {
                    sonosService.selectedGroup = nil
                }
#endif
        } else {
            // Anything dropped on the screen plays here, the way a drop on
            // a speaker plays on that group.
            content
                .dropDestinationPlayOnDevice()
        }
    }
}

// MARK: - Album, title, artist

/// The origin line: where this queue was played from, and a tap back into
/// it — the same slot, and the same job, as the container line the Sonos
/// player reads off the speaker.
///
/// The queue's `source` when there is one: the Plex playlist the row was
/// tapped in, the album that was played, the artist a run of tracks came
/// from. Only the album is on the track itself, so without the source a
/// track played out of a playlist named its album, which is where it lives
/// rather than where it was played from. Falls back to the album for a
/// queue with no origin — a search result, a hand-off from a speaker.
private struct LocalAlbumButton: View {
    @Environment(Router.self) private var router: Router

    let item: PlayableContent
    /// What the queue was played from, when it was played from anything.
    var source: PlayableContent?
    /// Stands in for the line while a station plays. A station has no album
    /// and no origin to open, so the line is text rather than a way in.
    var stationTitle: String?

    /// What the line names, and what a tap opens. The source before the
    /// album: it is the more specific answer, and the album is what's left
    /// when there is no source.
    private var origin: PlayableContent? {
        guard stationTitle == nil else { return nil }
        return source
    }

    private var title: String {
        stationTitle ?? origin?.title ?? item.metadata?.album ?? ""
    }

    /// Whichever of the two the tap would open has to have a screen to open
    /// — a source from a service with none leaves the line as plain text.
    private var isSupported: Bool {
        stationTitle == nil && (origin ?? item).content.service.supportsViewArtistAlbum
    }

    var body: some View {
        Button {
            guard isSupported else { return }
            HapticManager.shared.fireHaptic(.buttonPress)
            // An artist has its own screen; everything else — playlist,
            // album, folder — is a media detail.
            guard let origin else {
                return router.sheet(to: .mediaDetail(content: item, group: nil))
            }
            if origin.content.type.isArtist {
                router.sheet(to: .artistDetail(content: origin, group: nil))
            } else {
                router.sheet(to: .mediaDetail(content: origin, group: nil))
            }
        } label: {
            Text(title)
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .lineLimit(1, reservesSpace: true)
                .contentTransition(.identity)
        }
        .buttonStyle(.plain)
    }
}

/// Mirrors `LargePlayerView`'s song title: a marquee for a long name, and
/// a tap opens the album.
private struct LocalSongTitleButton: View {
    @Environment(Router.self) private var router: Router

    let item: PlayableContent
    /// What a tap opens in place of `item` — the song on a station.
    var target: PlayableContent? = nil

    @State private var isHovering: Bool = false

    private var isSupported: Bool { (target ?? item).content.service.supportsViewArtistAlbum }

    var body: some View {
        Button {
            guard isSupported else { return }
            HapticManager.shared.fireHaptic(.buttonPress)
            router.sheet(to: .mediaDetail(content: target ?? item, group: nil))
        } label: {
            MarqueeText(item.title)
                .bold()
                .multilineTextAlignment(.center)
                .fontDesign(.rounded)
                .font(.title2)
                .foregroundStyle(isHovering ? Color.primary.opacity(0.8) : Color.primary)
                .contentTransition(.identity)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard isSupported else { return }
            withAnimation(.interactiveSpring) {
                isHovering = hovering
            }
        }
    }
}

/// Mirrors `LargePlayerView`'s artist line: a tap opens the artist.
private struct LocalArtistButton: View {
    @Environment(Router.self) private var router: Router

    let item: PlayableContent
    /// What a tap opens in place of `item` — the song on a station.
    var target: PlayableContent? = nil
    let showArtworkOnly: Bool

    @State private var isHovering: Bool = false

    private var isSupported: Bool { (target ?? item).content.service.supportsViewArtistAlbum }

    var body: some View {
        Button {
            guard isSupported else { return }
            HapticManager.shared.fireHaptic(.buttonPress)
            router.sheet(to: .artistDetail(content: target ?? item, group: nil))
        } label: {
            Text(item.metadata?.artist ?? item.subtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(isHovering ? .primary : .secondary)
                .fontDesign(.rounded)
                .font(.title3)
                .frame(maxWidth: .infinity)
                .lineLimit(1, reservesSpace: true)
                .padding(.bottom, showArtworkOnly ? 100 : nil)
                .contentTransition(.identity)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard isSupported else { return }
            withAnimation(.interactiveSpring) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Scrubber and transport

/// The scrubber, mirroring `LargePlayerView.PlaybackView`: `VibeSlider` over
/// elapsed / audio quality / remaining, monospaced.
private struct LocalPlaybackScrubber: View {
    private var playback: LocalPlaybackService { .shared }

    /// Held only while dragging, so the poller's `progress` updates don't yank
    /// the thumb back under the finger mid-scrub.
    @State private var scrubPosition: TimeInterval?

    /// Twin of `LargePlayerView`'s: animating the fill is what makes playback
    /// tick along, but a track change drops the position to zero and animating
    /// *that* sweeps the bar backwards like a rewind.
    private var positionAnimation: Animation? {
        playback.progress < 2 ? nil : .interactiveSpring
    }

    /// Both kept finite here as well as in the service: everything below
    /// goes through `Duration.seconds(_:)`, which traps on NaN or infinity,
    /// and `max(_:_:)` passes a NaN straight through rather than flooring it.
    private var duration: TimeInterval {
        playback.duration.isFinite ? max(playback.duration, 1) : 1
    }

    /// Where the scrubber sits: the finger while dragging, the player's
    /// clock otherwise.
    private var position: TimeInterval {
        let value = scrubPosition ?? playback.progress
        return value.isFinite ? min(max(0, value), duration) : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            VibeSlider(
                value: Binding(
                    get: { position },
                    set: { scrubPosition = $0 }
                ),
                in: 0...duration,
                step: 1,
                baseHeight: UIDevice.current.userInterfaceIdiom == .phone ? 16 : 24,
                delayDrag: false,
                valueAnimation: positionAnimation
            ) { isEditing in
                guard !isEditing else { return }
                if let scrubPosition {
                    playback.seek(to: scrubPosition)
                }
                scrubPosition = nil
            }
            .frame(maxWidth: 500)
            .frame(height: 40)
            .foregroundStyle(.primary)
            .accessibilityLabel("Playback Position")
            .accessibilityValue(Duration.seconds(position).formatted(.time(pattern: .minuteSecond)))

            HStack {
                let elapsed = Duration.seconds(position)
                let remaining = Duration.seconds(max(0, duration - position))
                let pattern: Duration.TimeFormatStyle.Pattern =
                    duration > 3600 ? .hourMinuteSecond : .minuteSecond

                Text(elapsed.formatted(.time(pattern: pattern)))
                    .contentTransition(.identity)
                Spacer()
                // Lossless / Atmos / bit depth, as far as the backend says —
                // the badge the Sonos player draws from the speaker's report.
                AudioInfoView(quality: playback.audioQuality)
                    .frame(height: 12)
                    .contentTransition(.identity)
                    .animation(.spring, value: playback.audioQuality)
                Spacer()
                Text("-\(remaining.formatted(.time(pattern: pattern)))")
                    .contentTransition(.identity)
            }
            .frame(maxWidth: 500)
            .monospacedDigit()
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .opacity(playback.duration.isZero ? 0 : 1)
    }
}

/// Transport, mirroring `LargePlayerView.PlayerMediaControlsView`.
private struct LocalMediaControlsView: View {
    private var playback: LocalPlaybackService { .shared }

    /// A station has nothing to skip to, so it gets play/pause alone.
    private var isStation: Bool { playback.isPlayingStation }

    var body: some View {
        HStack {
            if !isStation {
                Button {
                    HapticManager.shared.fireHaptic(.selection)
                    playback.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.liveActivity)
                .accessibilityLabel("Previous")

                Spacer()
            }

            Button {
                HapticManager.shared.fireHaptic(.selection)
                playback.togglePlayback()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .resizable()
                    .scaledToFit()
                    .contentTransition(.symbolEffect(.automatic))
                    .symbolEffect(.pulse, isActive: playback.isLoading)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.liveActivity)
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            if !isStation {
                Spacer()

                Button {
                    HapticManager.shared.fireHaptic(.selection)
                    playback.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.liveActivity)
                .accessibilityLabel("Next")
                .disabled(!playback.hasNext)
            }
        }
        .frame(maxWidth: isStation ? nil : 300)
        .padding(.horizontal, 60)
    }
}

// MARK: - Volume

/// This device's volume in the shape of `VolumeControlView`: a minus, the
/// slider with its value, a plus. Greys out when the volume isn't ours to
/// move — see `DeviceVolume.isAvailable`.
private struct LocalVolumeControlView: View {
    @State private var volume = DeviceVolume.shared
    /// The value while a drag is in flight, so the slider tracks the finger
    /// instead of the system's stepped echo.
    @State private var dragging: Double?

    @ScaledMetric(relativeTo: .caption) private var sliderHeight: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 20 : 24

    /// One notch of the hardware buttons.
    private static let step: Double = 1.0 / 16.0

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                HapticManager.shared.fireHaptic(.selection)
                volume.set(volume.level - Self.step)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 24)
                    .bold()
            }
            .tint(.primary)
            .buttonStyle(.liveActivity)
            .buttonRepeatBehavior(.enabled)
            .accessibilityLabel("Volume Down")

            VibeSlider(
                value: Binding(
                    get: { (dragging ?? volume.level) * 100 },
                    set: { value in
                        dragging = value / 100
                        volume.set(value / 100)
                    }
                ),
                in: 0...100,
                step: 1,
                baseHeight: sliderHeight,
                delayDrag: false,
                showValue: true
            ) { editing in
                if !editing { dragging = nil }
            }
            .foregroundStyle(.primary)

            Button {
                HapticManager.shared.fireHaptic(.selection)
                volume.set(volume.level + Self.step)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
                    .bold()
            }
            .tint(.primary)
            .buttonStyle(.liveActivity)
            .buttonRepeatBehavior(.enabled)
            .accessibilityLabel("Volume Up")
        }
        .font(.caption)
        .fontDesign(.rounded)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .tint(.primary)
        .disabled(!volume.isAvailable)
        .opacity(volume.isAvailable ? 1 : 0.4)
        .animation(.spring, value: volume.isAvailable)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((volume.level * 100).rounded())) percent")
    }
}

// MARK: - Bottom toolbar

/// The glass row under the volume, in the shape of `LargePlayerView`'s
/// `BottomToolbarView`: the route picker where the Sonos player has its
/// group button — on a speaker its menu is the regroup menu too, so there is
/// no second speaker button beside it; then the room volume for a group of
/// more than one, and the queue on the trailing edge on a phone. No search
/// or browse: the window's tabs are a dismiss away on every size, and the
/// cover's sheets only doubled them. The wide row has no queue: iPad's is
/// in the navigation bar, the Mac's in the window toolbar. The
/// like button and the menu live in the navigation bar on every size, so this row
/// is only ever about where to go next.
private struct PlayerBottomToolbarView: View {
    @Environment(Router.self) private var router: Router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The group on screen, or `nil` for this device.
    let group: GroupRoom?
    @Binding var showQueue: Bool

    @State private var isHoveringOnQueueList: Bool = false

    private var playback: LocalPlaybackService { .shared }

    var body: some View {
        @Bindable var router = router

        if UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact {
            HStack(spacing: 0) {
                PlaybackRouteButton()
                    .buttonStyle(.plain)
                    .imageScale(.large)

                if let group, group.rooms.count > 1 {
                    Spacer()
                    roomVolumeButton(group)
                        .buttonStyle(.plain)
                        .imageScale(.large)
                        .withPopoverDestinations(popoverDestination: $router.volumePopover)
                }

                // A station's song, a tap away on the bar rather than
                // down in the menu.
                if IdentifySongButton.isAvailable(for: group) {
                    Spacer()
                    IdentifySongButton(group: group)
                        .buttonStyle(.plain)
                        .imageScale(.large)
                }

                // No search or browse on a phone: the tab bar is a swipe
                // down away, and the cover's search sheet only doubled it.
                Spacer()
                queueButton
                    .buttonStyle(.plain)
                    .imageScale(.large)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .frame(maxWidth: 500)
            .glassToolbar()
        } else {
            // No queue button: at this width it's in the navigation bar on
            // iPad, and the window toolbar's on the Mac.
            HStack {
                PlaybackRouteButton()
                    .buttonBorderShape(.roundedRectangle)
                    .glassButton()
                    .help("Play On")

                if let group, group.rooms.count > 1 {
                    roomVolumeButton(group)
                        .buttonBorderShape(.roundedRectangle)
                        .glassButton()
                        .withPopoverDestinations(popoverDestination: $router.volumePopover)
                        .help("Speaker Control")
                }

                if IdentifySongButton.isAvailable(for: group) {
                    IdentifySongButton(group: group)
                        .buttonBorderShape(.roundedRectangle)
                        .glassButton()
                }
            }
        }
    }

    private func roomVolumeButton(_ group: GroupRoom) -> some View {
        Button {
            router.volumePopover = .volumeControlsScreen(groupID: group.coordinatorID)
        } label: {
            Label("Room Volume", systemImage: "speaker.wave.2.fill")
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 24)
                .labelStyle(.iconOnly)
                .fontDesign(.rounded)
        }
    }

    /// The queue toggle with its gauge — the device's or the group's — and
    /// the play mode badge over it. A drop on it plays next wherever the
    /// route points.
    @ViewBuilder
    private var queueButton: some View {
        let button = Button {
            HapticManager.shared.fireHaptic(.selection)
            withAnimation {
                showQueue.toggle()
            }
        } label: {
            Group {
                if let group {
                    QueueIconView(group: group)
                } else {
                    LocalQueueIconView()
                }
            }
            .fontDesign(.rounded)
            .font(.title3)
            .foregroundStyle(isHoveringOnQueueList || showQueue ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
            .overlay(alignment: .topTrailing) {
                if isHoveringOnQueueList {
                    Image(systemName: "plus.circle.fill")
                        .offset(x: 12, y: -18)
                        .transition(.scale)
                        .foregroundStyle(.green.gradient)
                }
            }
        }
        .accessibilityLabel("Up Next")
        .accessibilityAddTraits(showQueue ? .isSelected : [])
        .overlay(alignment: .topTrailing) {
            playModeBadge
        }

        if let group {
            button
                .accessibilityValue(group.playMode.accessibilityDescription)
                .dropDestinationPlay(on: group, position: .next) { isTargeted in
                    if isTargeted {
                        HapticManager.shared.fireHaptic(.selection)
                    }
                    withAnimation {
                        isHoveringOnQueueList = isTargeted
                    }
                }
        } else {
            button
                .disabled(playback.queue.isEmpty)
                .dropDestinationPlayOnDevice(position: .next) { isTargeted in
                    if isTargeted {
                        HapticManager.shared.fireHaptic(.selection)
                    }
                    withAnimation {
                        isHoveringOnQueueList = isTargeted
                    }
                }
        }
    }

    /// Shuffle or repeat, whichever is on where the route points.
    private var playModeSymbol: String? {
        if let group {
            if group.playMode.contains(.shuffle) { return "shuffle.circle.fill" }
            if group.playMode.contains(.repeatAll) { return "repeat.circle.fill" }
            if group.playMode.contains(.repeatOne) { return "repeat.1.circle.fill" }
            return nil
        }
        switch playback.repeatMode {
        case .all: return "repeat.circle.fill"
        case .one: return "repeat.1.circle.fill"
        case .off: return nil
        }
    }

    @ViewBuilder
    private var playModeBadge: some View {
        if let symbol = playModeSymbol {
            Image(systemName: symbol)
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(.black.secondary)
                .offset(x: 10, y: -10)
        }
    }
}

/// The queue gauge, mirroring `QueueIconView`: how far through the device's
/// queue playback is, with the position in the middle.
private struct LocalQueueIconView: View {
    private var playback: LocalPlaybackService { .shared }

    @ScaledMetric(relativeTo: .caption2) private var iconSize: CGFloat = 24

    var body: some View {
        let position = playback.queue.isEmpty ? 0 : playback.currentIndex + 1
        VibeGaugeView(value: Double(position),
                      total: Double(playback.queue.count),
                      color: .primary,
                      lineWidth: 2)
        .overlay {
            Text(position, format: .number)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 4)
                .allowsTightening(true)
                .font(.caption2.monospacedDigit())
                .contentTransition(.numericText())
        }
        .animation(.spring, value: playback.currentIndex)
        .fontDesign(.rounded)
        .frame(width: iconSize, height: iconSize)
        .accessibilityLabel("Up Next")
    }
}

// MARK: - Menu

/// The ellipsis menu, in the shape of `MenuInfoView`: open in the service,
/// the album and artist screens, playlists, handing the track to a speaker,
/// the controls toggle, downloads, and a control group of shuffle, repeat
/// and the sleep timer.
private struct LocalPlayerMenuView: View {
    @Environment(Router.self) private var router: Router

    let item: PlayableContent
    @Binding var showArtworkOnly: Bool

    private var playback: LocalPlaybackService { .shared }

    /// What the song actions act on: the song on air while a station plays
    /// and Apple Music has it, else the row itself. Playing elsewhere and
    /// downloads stay with the row.
    private var song: PlayableContent { playback.onAirMatch ?? item }

    var body: some View {
        Menu {
            OpenInServiceView(item: song)
            if song.content.service.supportsViewArtistAlbum {
                Button {
                    router.sheet(to: .mediaDetail(content: song, group: nil))
                } label: {
                    Label("View Album", systemImage: "smallcircle.circle.fill")
                }

                Button {
                    router.sheet(to: .artistDetail(content: song, group: nil))
                } label: {
                    Label("View Artist", systemImage: "music.mic")
                }
            }

            // A station itself can't go in a playlist; the song on it can.
            if !song.content.type.isRadio {
                Divider()
                AddToLastPlaylistButton(itemToAdd: song)
                Button {
                    router.sheet(to: .addToPlaylist(content: song))
                } label: {
                    Label("Add to Playlist…", systemImage: "text.badge.plus")
                }
            }
            Divider()

            Toggle(isOn: $showArtworkOnly) {
                Label("\(showArtworkOnly ? "Show" : "Hide") controls", systemImage: "photo")
            }

            LocalDownloadMenuSection(item: item)

            ControlGroup {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    playback.shuffleUpNext()
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .disabled(playback.upNext.count < 2)

                Button {
                    HapticManager.shared.fireHaptic(.selection)
                    playback.setRepeatMode(playback.repeatMode.next)
                } label: {
                    Label(playback.repeatMode.title, systemImage: playback.repeatMode.systemImage)
                }
                .menuActionDismissBehavior(.disabled)
                .tint(playback.repeatMode == .off ? .secondary : .accent)

                TimerMenuView(sheetRouter: router, onSelect: {
                    await playback.sleepTimer($0)
                }, onClear: {
                    await playback.cancelSleepTimer()
                }, onSleepAtEndOfTrack: {
                    await playback.sleepAtEndOfTrack()
                }) {
                    Label("Sleep Timer", systemImage: "deskclock.fill")
                }
            }

        } label: {
            Label("Menu", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .frame(width: 24, height: 24)
        }
        .accessibilityLabel("Menu")
        .help("Menu")
        .onAppear {
            AppleDownloadsIndex.shared.refreshIfNeeded()
        }
#if os(visionOS)
        .tint(.clear)
#endif
    }
}

// MARK: - Background

/// The blurred-artwork backdrop, mirroring `LargePlayerView`'s
/// `BackgroundViewCatalyst` / `BackgroundView`. Catalyst blurs the image
/// directly and lays a `UIVisualEffectView` over it; elsewhere the artwork is
/// scaled to fill under a thin material, which is cheaper on device.
private struct PlayerBackgroundView: View {
    let content: PlayableContent?

    var body: some View {
        ZStack {
            if let content {
#if targetEnvironment(macCatalyst)
                ContentArtworkView(content: content, showMusicSource: false, preferredSize: 600)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .saturation(1.3)
                    .blur(radius: 80)
                BlurView()
#else
                ContentArtworkView(content: content, showMusicSource: false, preferredSize: 600)
                    .saturation(1.3)
                    .aspectRatio(contentMode: .fill)
                Rectangle()
                    .foregroundStyle(.thinMaterial)
#endif
            }
        }
        .scaleEffect(1.3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
