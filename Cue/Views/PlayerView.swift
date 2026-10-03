import Defaults
import MediaPlayer
import MusicSearchKit
import SonosKit
import SwiftUI
import VibesDS

/// The player: full screen, opened from the tab bar accessory, showing
/// whatever the route points at — this device, or the Sonos group chosen
/// in the route button.
///
/// One layout for both, read through `PlaybackController`
/// (`PlaybackRoute.presented`): the title, the scrubber and the transport
/// are the same views whichever way the route points, so switching it
/// changes what they read, not what's on screen. While a switch carries the
/// queue across, `presented` stays on the source until the target is
/// playing the same song, so the player carries on with that song through
/// the hand-off rather than showing the speaker's last track in between.
/// Only what a speaker alone has — its artwork view with the mute and alarm
/// badges, TV mode, its menu, the room volume — looks at the group itself.
///
/// The navigation bar has no title, only the sleep timer, the like button
/// and the menu; below it the artwork, the album line,
/// the title and the artist (each opening its detail), the scrubber with
/// the audio-quality badge, the transport, the volume row with its
/// steppers, and the bottom row: the route picker in the middle and the
/// queue at the trailing edge.
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

    /// What the player draws and its controls act on.
    private var controller: any PlaybackController { route.presented }

    /// The speaker on screen, for what only a speaker has. Resolved on every
    /// read: a topology refresh replaces every `GroupRoom`, so nothing here
    /// holds one.
    private var group: GroupRoom? { route.presentedGroup }

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

    /// The phone's layout, after the system's Now Playing: the artwork at
    /// the top and the title and controls spread down the rest of the
    /// screen, with bigger transport. iPad and the Mac keep the tight stack.
    private var isPhoneLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// Only on the Mac, where the player slides up instead of zooming. On
    /// iPhone and iPad the artwork fills most of the screen, and the drag
    /// interaction behind `.draggable` claims the touch before the zoom's
    /// swipe-down-to-dismiss can, so pulling down on the cover did nothing.
    private var isArtworkDraggable: Bool {
#if targetEnvironment(macCatalyst)
        true
#else
        false
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

    var body: some View {
        // The stack sits inside the queue panel, so its bar spans the player
        // column only, and the backdrop is drawn behind both from outside.
        // An earlier stack here lost the zoom out of the mini player; if it
        // goes again, that's where to look.
        NavigationStack {
            VStack(alignment: .center) {
                // TV mode is the one screen of its own: a soundbar on TV
                // has no song, cover or transport to show.
                if let group, group.TVMode {
                    tvContent(group)
                } else {
                    playerContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.interactiveSpring, value: showArtworkOnly)
            // A change of source is never animated: the sections carry on
            // with what the new one reads, in place. On the Mac an animated
            // swap of the whole player cost a fixed ~90 MB of GPU memory for
            // ~2 s.
            .transaction(value: route.presentedDestination) { transaction in
                transaction.animation = nil
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            // The stack already keeps clear of the home indicator; padding
            // by the inset again left the phone's bottom row floating a
            // home indicator's height too high.
            .safeAreaPadding(.bottom, isPhoneLayout ? 0 : nil)
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
        // The speaker's socket, sleep timer, play mode and hardware volume;
        // a drop on the screen plays wherever the route points. The route's
        // group rather than the one on screen: a switch to a speaker opens
        // its socket at once, which is what brings the carried song's
        // report in for the player to go over on.
        .modifier(PlayerSessionModifier(coordinatorID: route.group?.coordinatorID, shouldFade: $shouldFade))
        .fontDesign(.rounded)
        .environment(router)
        .withEnvironments()
    }

    /// The blurred artwork behind the whole cover, queue panel included.
    ///
    /// Clipped to the cover: the backdrop is scaled up and blurred past its
    /// edges, and the Mac's plain slide-down cover doesn't clip its content
    /// the way the zoom does. Unclipped, the overhang above the cover's top
    /// edge was left sitting over the bottom of the window — covering the
    /// mini player — until the dismiss finished.
    ///
    /// `ignoresSafeArea` goes outside the clip so the clip is laid out at the
    /// full cover, title bar included; clipped at the safe area instead, the
    /// backdrop stopped short of the window's top edge.
    private var backdrop: some View {
        PlayerBackdrop(group: group, content: group == nil ? playback.nowPlayingDisplay : nil)
            .clipped()
            .ignoresSafeArea()
    }

    // MARK: - The player

    /// The cover, the three lines under it, the scrubber, the transport, the
    /// volume and the bottom row, for either source.
    ///
    /// With nothing playing the player keeps its shape — an empty cover,
    /// "Not Playing", the transport greyed out — so the route picker, the
    /// volume and the queue are where they always are, rather than a blank
    /// "Nothing Playing" screen with no way to do anything.
    @ViewBuilder
    private var playerContent: some View {
        artwork
            .padding(.bottom, showArtworkOnly ? 0 : 12)
            .frame(minWidth: 0, maxWidth: showArtworkOnly ? .infinity : (isMacCatalystOrPad ? 800 : 500), minHeight: 0, maxHeight: showArtworkOnly ? .infinity : (isMacCatalystOrPad ? .infinity : 400))
            .padding(.top, showArtworkOnly ? 100 : nil)
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.size.height >= 100
            } action: { isArtworkVisible = $0 }
            .opacity(isArtworkVisible ? 1 : 0)
            .animation(.interactiveSpring, value: isArtworkVisible)
            // Sized before the spacers below share out what's left; at an
            // equal priority they split the height with it and the cover
            // shrank to a thumbnail.
            .layoutPriority(isPhoneLayout ? 1 : 0)

        if isPhoneLayout {
            Spacer(minLength: 12)
            titleLines

            if !showArtworkOnly {
                Group {
                    PlayerScrubber()
                        .padding(.top, 4)
                    Spacer(minLength: 4)
                    PlayerTransportView(shouldFade: $shouldFade, isProminent: true)
                    Spacer(minLength: 4)
                    volumeRow
                        .padding(.horizontal, -12)
                        .frame(maxWidth: 500)
                    PlayerBottomToolbarView(group: group, showQueue: $showQueue)
                }
                .transition(.opacity.combined(with: .push(from: .bottom)))
            }
        } else {
            titleLines

            if !showArtworkOnly {
                VStack {
                    PlayerScrubber()
                    PlayerTransportView(shouldFade: $shouldFade)
                }
                .geometryGroup()
                .transition(.opacity.combined(with: .push(from: .bottom)))

                VStack {
                    volumeRow
                        .padding(.bottom, 20)
                        .padding(.horizontal, -12)
                        .frame(maxWidth: 500)

                    PlayerBottomToolbarView(group: group, showQueue: $showQueue)
                }
                .transition(.opacity)
            }
        }
    }

    /// The cover, or Live Transcription in its place — in the same frame, so
    /// the controls below don't move when it's switched. A speaker's cover is
    /// `ArtworkView`, which carries its mute and alarm badges and shares the
    /// Lock Screen's cache entry; a hand-off goes over to it only once that
    /// entry holds the carried song's cover (see `PlaybackRoute.hold`), so
    /// it draws on its first frame.
    @ViewBuilder
    private var artwork: some View {
        if showsTranscription {
            LiveTranscriptionView()
                .transition(.opacity)
        } else if let group {
            ArtworkView(group: group, isDraggable: isArtworkDraggable, showBadge: true, shouldFade: artworkShouldFade)
                .transition(.opacity)
        } else if let item = playback.nowPlayingDisplay {
            ContentArtworkView(content: item, showMusicSource: true, preferredSize: 600, cornerRadius: 8, isDraggable: isArtworkDraggable)
                .shadow(radius: 2)
                .transition(.opacity)
        } else {
            EmptyPlayerArtwork()
                .transition(.opacity)
        }
    }

    /// Where the song plays from, the title and the artist. The display item
    /// for either source — a station's song on air on this device, the
    /// speaker's current track — and the same three lines holding their
    /// places with nothing playing.
    @ViewBuilder
    private var titleLines: some View {
        let item = controller.nowPlayingDisplay
        // While a station plays here, a tap opens the song on air once Apple
        // Music has it — named by the station or by Shazam.
        let target = group == nil ? (playback.onAirMatch ?? item) : item

        originLine(item)
        PlayerSongTitleButton(
            title: item?.title ?? (controller.isActive ? "" : "Not Playing"),
            target: target,
            group: group
        )
        PlayerArtistButton(
            artist: item.map { $0.metadata?.artist ?? $0.subtitle } ?? "",
            target: target,
            group: group,
            showArtworkOnly: showArtworkOnly
        )
    }

    /// Where the song is playing from, in a fixed caption-high slot so the
    /// layout doesn't shift between songs that have one and songs that
    /// don't: the speaker's playlist, album or station, or what this
    /// device's queue was played from.
    @ViewBuilder
    private func originLine(_ item: PlayableContent?) -> some View {
        if let group {
            groupContainerLine(group)
        } else if let item {
            LocalAlbumButton(
                item: item,
                source: playback.source,
                stationTitle: item.content.type.isRadio ? (playback.nowPlaying?.title ?? "") : nil
            )
            .frame(height: 12)
        } else {
            Color.clear
                .frame(height: 12)
        }
    }

    /// The playlist or album the speaker is playing from, or the station.
    private func groupContainerLine(_ group: GroupRoom) -> some View {
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
        // Resolve the label's layout inside this fixed frame so a newly
        // inserted or changed label fades in place instead of flying in from
        // its old/zero position.
        .geometryGroup()
        .frame(height: 12)
    }

    /// The volume of what's on screen: the speaker's group volume, or this
    /// device's. Two views, one shape — a minus, the slider with its value,
    /// a plus — so the row stays put when the source changes.
    @ViewBuilder
    private var volumeRow: some View {
        if let group {
            VolumeControlView(group: group)
        } else {
            LocalVolumeControlView()
        }
    }

    // MARK: - TV mode

    /// A soundbar on TV: the TV glyph and its controls in place of artwork
    /// and transport, then the volume and the bottom row as ever.
    @ViewBuilder
    private func tvContent(_ group: GroupRoom) -> some View {
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

        VStack {
            VolumeControlView(group: group)
                .padding(.bottom, 20)
                .padding(.horizontal, -12)
                .frame(maxWidth: 500)

            PlayerBottomToolbarView(group: group, showQueue: $showQueue)
        }
        .transition(.opacity)
    }

    /// The like button and the menu for this device, in the navigation bar.
    @ViewBuilder
    private func localNavigationButtons(_ item: PlayableContent) -> some View {
        // The song on air, while a station plays and Apple Music has it.
        if let song = playback.onAirMatch {
            LikeButtonView(content: song)
                .id(song.content.id)
        } else if item.content.service.supportsFavoriteTrack {
            LikeButtonView(content: item)
        }
        LocalPlayerMenuView(item: item, showArtworkOnly: $showArtworkOnly)
            .tint(.primary)
    }

    // MARK: - Toolbar

    /// No title (only a close chevron leading on the Mac), and trailing
    /// the sleep timer, the like button and the menu — up here on every size, so the bar below
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
            // A speaker's menu has its own extras — grouping, EQ, the TV —
            // so the two stay separate views in the one slot.
            if let group {
                LikeButtonView(group: group)
                MenuInfoView(group: group, showArtworkOnly: $showArtworkOnly)
                    .tint(.primary)
                    .modifier(GroupRefreshOnForegroundModifier())
            } else if let item = playback.nowPlaying {
                localNavigationButtons(item)
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

    /// The sleep timer chip for what's on screen, or `nil` while no timer is
    /// set there.
    private var sleepTimerChip: AnyView? {
        let controller = self.controller
        // A timer left on this device with nothing queued has nothing to
        // pause; a speaker's is the speaker's whatever it's playing.
        guard controller.group != nil || controller.isActive else { return nil }
        if let date = controller.sleepTimerEndDate, date > Date.now {
            return AnyView(sleepTimerChip(on: controller.name) {
                Text(date, style: .timer)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.spring, value: date)
                    .monospacedDigit()
                    .bold()
            } cancel: {
                Task { await controller.cancelSleepTimer() }
            })
        }
        if controller.sleepsAtEndOfTrack {
            return AnyView(sleepTimerChip(on: controller.name) {
                Text("End of Song")
                    .bold()
            } cancel: {
                Task { await controller.cancelSleepTimer() }
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

/// What the speaker the route points at needs kept alive — its metadata
/// socket, the crossfade flag, sleep timer and play mode reads, the
/// scene-phase sync, hardware volume — the same set `LargePlayerView` runs,
/// and where a drop on the screen goes.
///
/// One chain whichever way the route points, with no group for this device.
/// Branching on the group here put the whole player in one of two
/// branches, so every route change built it again from scratch.
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
        content
            // Anything dropped on the screen plays where the route points.
            .dropDestinationPlay(onGroupOrDevice: group)
            .hardwareVolumeControl(group: group)
            .modifier(GroupScenePhaseSyncModifier(coordinatorID: coordinatorID))
            .task(id: coordinatorID) {
                guard let group = self.group else { return }
                // Re-points the `.viewing` listener; the registry closes
                // the previous group's socket unless another listener
                // still needs it.
                await sonosService.getTrackAudioInformation(ip: group.ip, playerID: group.coordinatorID, groupID: group.id)
                group.isCrossfaded = await sonosService.isCrossfaded(for: group)
                await sonosService.getSleepTimer(group: group)
            }
            .task(id: coordinatorID) {
                guard let group = self.group else { return }
                sonosService.selectedGroup = group
                try? await sonosService.updateTrackInformation(for: [group])
            }
            .task(id: coordinatorID) {
                guard let group = self.group else { return }
                let awaitedPlayMode = await sonosService.playMode(ip: group.ip)
                if group.playMode != awaitedPlayMode {
                    group.playMode = awaitedPlayMode
                }
                try? await Task.sleep(for: .milliseconds(400))
                shouldFade = true
            }
            .onChange(of: coordinatorID) { _, id in
                shouldFade = false
#if !targetEnvironment(macCatalyst)
                // The route left the speakers: the same as the speaker's
                // player closing.
                if id == nil {
                    sonosService.selectedGroup = nil
                }
#endif
            }
#if !targetEnvironment(macCatalyst)
            .onDisappear {
                guard coordinatorID != nil else { return }
                sonosService.selectedGroup = nil
            }
#endif
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

/// The song's title, for either source: a marquee for a long name, and a
/// tap opens the album — the speaker's track, or this device's song (the
/// song on air, on a station, once Apple Music has it).
private struct PlayerSongTitleButton: View {
    @Environment(Router.self) private var router: Router

    let title: String
    /// What a tap opens, when there's anything to open.
    let target: PlayableContent?
    /// The speaker on screen, which the detail screen plays on.
    let group: GroupRoom?

    @State private var isHovering: Bool = false

    private var isSupported: Bool { target?.content.service.supportsViewArtistAlbum ?? false }

    var body: some View {
        Button {
            guard isSupported, let target else { return }
            HapticManager.shared.fireHaptic(.buttonPress)
            router.sheet(to: .mediaDetail(content: target, group: group))
        } label: {
            MarqueeText(title)
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

/// The artist line, for either source: a tap opens the artist.
private struct PlayerArtistButton: View {
    @Environment(Router.self) private var router: Router

    let artist: String
    /// What a tap opens, when there's anything to open.
    let target: PlayableContent?
    /// The speaker on screen, which the detail screen plays on.
    let group: GroupRoom?
    let showArtworkOnly: Bool

    @State private var isHovering: Bool = false

    private var isSupported: Bool { target?.content.service.supportsViewArtistAlbum ?? false }

    var body: some View {
        Button {
            guard isSupported, let target else { return }
            HapticManager.shared.fireHaptic(.buttonPress)
            router.sheet(to: .artistDetail(content: target, group: group))
        } label: {
            Text(artist)
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

/// The cover's place with nothing queued: a blank cover with a note in it,
/// the shape `ContentArtworkView` gives a missing image.
private struct EmptyPlayerArtwork: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 72))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("No Artwork")
    }
}

// MARK: - Scrubber and transport

/// The scrubber, for either source: `VibeSlider` over elapsed / audio
/// quality / remaining, monospaced, redrawn from the running clock once per
/// pixel of progress (see `PlaybackTimeline`). Reads
/// `PlaybackRoute.presented`, in seconds whichever it is, so a route switch
/// changes what it reads and nothing else.
private struct PlayerScrubber: View {
    private var route: PlaybackRoute { .shared }

    @Environment(\.displayScale) private var displayScale

    /// Held only while dragging, so the thumb stays under the finger rather
    /// than running on with the clock — and until the seek has been sent,
    /// so the bar doesn't jump back to the old spot in between.
    @State private var scrubPosition: TimeInterval?
    /// True while a finger is on the bar. `VibeSlider` reports `true` on
    /// every movement, not only the first touch.
    @State private var isScrubbing = false
    /// The bar's width, which sets how often it's worth redrawing.
    @State private var barWidth: CGFloat = 0

    /// Kept finite here as well as in the services: everything below goes
    /// through `Duration.seconds(_:)`, which traps on NaN or infinity, and
    /// `max(_:_:)` passes a NaN straight through rather than flooring it.
    /// Floored at one so the slider's range is never empty — a station has
    /// no length, and the row is hidden for one anyway.
    private func range(of controller: any PlaybackController) -> TimeInterval {
        let duration = controller.duration
        return duration.isFinite ? max(duration, 1) : 1
    }

    private func clamped(_ value: TimeInterval, to duration: TimeInterval) -> TimeInterval {
        value.isFinite ? min(max(0, value), duration) : 0
    }

    var body: some View {
        let controller = route.presented
        let duration = range(of: controller)
        // While a hand-off holds the player, the source is paused on its way
        // out; the bar runs on from where the switch was made, as the target
        // will (see `PlaybackRoute.Hold`).
        let hold = route.hold
        // Paused under a finger, while nothing plays, and off screen (see
        // `PlaybackTimeline`). A seek or a new song lands at once rather than
        // sweeping, hence no value animation.
        PlaybackTimeline(
            isRunning: (hold?.wasPlaying ?? controller.isClockRunning) && scrubPosition == nil,
            minimumInterval: ProgressRedraw.interval(
                forDuration: duration * 1000,
                length: barWidth,
                scale: displayScale
            ),
            position: { clamped(scrubPosition ?? hold?.position(at: .now) ?? controller.position(), to: duration) }
        ) { position in
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
                    valueAnimation: nil
                ) { isEditing in
                    scrubbingChanged(isEditing, on: controller)
                }
                .frame(maxWidth: 500)
                .frame(height: 40)
                .foregroundStyle(.primary)
                .accessibilityLabel("Playback Position")
                .accessibilityValue(Duration.seconds(position).formatted(.time(pattern: .minuteSecond)))
                // Nothing to seek while a hand-off holds the player on its
                // source, which is on its way out.
                .disabled(!controller.canScrub || route.isHolding)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }

                HStack {
                    let elapsed = Duration.seconds(position)
                    let remaining = Duration.seconds(max(0, duration - position))
                    let pattern: Duration.TimeFormatStyle.Pattern =
                        duration > 3600 ? .hourMinuteSecond : .minuteSecond

                    Text(elapsed.formatted(.time(pattern: pattern)))
                        .contentTransition(.identity)
                    Spacer()
                    // Lossless / Atmos / bit depth, as far as the backend or
                    // the speaker says.
                    AudioInfoView(quality: controller.audioQuality)
                        .frame(height: 12)
                        .contentTransition(.identity)
                        .animation(.spring, value: controller.audioQuality)
                    Spacer()
                    Text("-\(remaining.formatted(.time(pattern: pattern)))")
                        .contentTransition(.identity)
                }
                .frame(maxWidth: 500)
                .monospacedDigit()
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .opacity(controller.duration.isZero ? 0 : 1)
    }

    private func scrubbingChanged(_ isEditing: Bool, on controller: any PlaybackController) {
        if isEditing {
            guard !isScrubbing else { return }
            isScrubbing = true
            controller.beginScrubbing()
        } else {
            guard isScrubbing else { return }
            isScrubbing = false
            let target = scrubPosition
            Task { @MainActor in
                await controller.endScrubbing(at: target)
                // A new drag since has its own position.
                if !isScrubbing {
                    scrubPosition = nil
                }
            }
        }
    }
}

/// Transport, for either source. A station on this device has nothing to
/// go back to, and a live stream nothing to skip to either, so it gets
/// play/pause alone (an Apple Music station is a stream of songs, so it
/// keeps Next); a speaker greys out what its transport doesn't offer.
///
/// While a hand-off holds the player on its source (`PlaybackRoute.hold`)
/// the buttons rest, the play button pulsing and reading as the source did
/// when the switch was made: the source is coming down and the target isn't
/// up yet, so there's nothing for them to act on that wouldn't race the
/// hand-off.
private struct PlayerTransportView: View {
    private var route: PlaybackRoute { .shared }

    /// The speaker artwork's crossfade window, closed around a skip so a
    /// deliberate change snaps — see `GroupMediaControlsView`.
    @Binding var shouldFade: Bool
    /// The phone's player — see `GroupMediaControlsView.isProminent`.
    var isProminent: Bool = false

    @State private var skipTask: Task<Void, Never>?

    private var skipSize: CGFloat { isProminent ? 38 : 32 }
    private var playSize: CGFloat { isProminent ? 40 : 32 }

    private enum Skip {
        case previous
        case next
    }

    var body: some View {
        let controller = route.presented
        let hold = route.hold
        let isPlaying = hold?.wasPlaying ?? controller.isPlaying
        // A load that's over in a moment doesn't pulse; one that keeps the
        // song waiting does (see `sustainedPulse`).
        let isLoading = hold != nil || controller.isLoading

        HStack {
            if controller.showsPrevious {
                Button {
                    skip(.previous)
                } label: {
                    Image(systemName: "backward.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: skipSize, height: skipSize)
                }
                .buttonStyle(.liveActivity)
                .accessibilityLabel("Previous")
                .disabled(!controller.canGoBack)

                Spacer()
            } else if controller.showsNext {
                // Holds Previous's place so Play stays centred.
                Color.clear
                    .frame(width: skipSize, height: skipSize)
                    .accessibilityHidden(true)

                Spacer()
            }

            Button {
                HapticManager.shared.fireHaptic(.selection)
                Task { await controller.togglePlayback() }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .resizable()
                    .scaledToFit()
                    .contentTransition(GroupMediaControlsView.playPauseTransition)
                    .sustainedPulse(isActive: GroupMediaControlsView.animatesPlayPause && isLoading)
                    .frame(width: playSize, height: playSize)
            }
            .buttonStyle(.liveActivity)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            #if DEBUG && !targetEnvironment(macCatalyst)
            .keyboardShortcut(.space, modifiers: [])
            #endif

            if controller.showsNext {
                Spacer()

                Button {
                    skip(.next)
                } label: {
                    Image(systemName: "forward.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: skipSize, height: skipSize)
                }
                .buttonStyle(.liveActivity)
                .accessibilityLabel("Next")
                .disabled(!controller.hasNext)
            }
        }
        .frame(maxWidth: controller.showsNext ? (isProminent ? 320 : 300) : nil)
        .padding(.horizontal, isProminent ? 36 : 60)
        // Nothing loaded: there, so the player keeps its shape, but nothing
        // to press. Nor while a hand-off holds it.
        .disabled(!controller.isActive || hold != nil)
    }

    /// Skips on whatever is on screen. Instant on both: this device moves at
    /// once, and a speaker shows the new song before it has moved
    /// (`SonosService+TrackSkip.swift`).
    private func skip(_ direction: Skip) {
        let controller = route.presented
        skipTask?.cancel()
        skipTask = Task { @MainActor in
            HapticManager.shared.fireHaptic(.selection)
            shouldFade = false
            switch direction {
            case .previous: await controller.previous()
            case .next: await controller.next()
            }
            // Holds the speaker artwork's no-fade window open until well
            // past the socket's push of the new track: `ArtworkView`
            // snapshots `shouldFade` when the URL changes.
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            shouldFade = true
        }
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
#if os(iOS) && !targetEnvironment(macCatalyst)
        // While this row is up, the system's volume HUD stays away: iOS
        // hides it whenever an `MPVolumeView` is on screen, and this slider
        // already shows the level the buttons move.
        .background {
            HiddenSystemVolumeView()
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
        }
#endif
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
/// An invisible `MPVolumeView`, there only so the system skips its HUD.
/// Not `isHidden` or zero alpha — iOS treats those as off screen and shows
/// the HUD anyway.
private struct HiddenSystemVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.alpha = 0.0001
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
#endif

// MARK: - Bottom toolbar

/// The row under the volume. On a phone it has no glass: the route picker
/// in the middle — on a speaker its menu is the regroup menu too — and the
/// queue on the trailing edge, with the leading slot empty for now. The
/// wide row adds the room volume for a group of more than one and Identify
/// Song. No search
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

    private var route: PlaybackRoute { .shared }

    /// The group the route picker plays on, or `nil` on this device. The
    /// group on screen first, then the route's, so a solo room reads too.
    /// While a hand-off holds the player on its source, where it's going.
    private var routeName: String? {
        if route.isHolding {
            return "Moving to \(route.group?.nameWithCount ?? "This Device")…"
        }
        return (group ?? route.group)?.nameWithCount
    }

    var body: some View {
        @Bindable var router = router

        if UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact {
            // No glass: the route picker centred and the queue trailing,
            // with the leading slot left empty for now.
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: 1)

                    PlaybackRouteButton()
                        .buttonStyle(.plain)
                        .imageScale(.large)
                        .frame(maxWidth: .infinity)

                    queueButton
                        .buttonStyle(.plain)
                        .imageScale(.large)
                        .frame(maxWidth: .infinity)
                }

                // The speaker it plays on, on its own line under the route
                // picker. Laid out here rather than in the picker's label:
                // iOS flattens a Menu's label, and an overlay on the Menu
                // gets clipped by the button behind it.
                HStack(spacing: 0) {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    Text(routeName ?? " ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity)
                        .opacity(routeName == nil ? 0 : 1)
                        .accessibilityHidden(true)
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, UIDevice.current.userInterfaceIdiom == .phone ? 0 : 14)
            .padding(.horizontal, 28)
            .frame(maxWidth: 500)
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
            PresentedQueueIconView()
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

        // One button whichever way the route points, so it keeps its place
        // (and its hover state) when the route changes. The drop goes where
        // the route points, even while the player still shows the source.
        button
            .accessibilityValue(group?.playMode.accessibilityDescription ?? "")
            .disabled(group == nil && playback.queue.isEmpty)
            .dropDestinationPlay(onGroupOrDevice: route.group, position: .next) { isTargeted in
                if isTargeted {
                    HapticManager.shared.fireHaptic(.selection)
                }
                withAnimation {
                    isHoveringOnQueueList = isTargeted
                }
            }
    }

    /// Shuffle or repeat, whichever is on for what's on screen. Shuffle
    /// first: a speaker can have both.
    private var playModeSymbol: String? {
        let controller = route.presented
        if controller.isShuffled { return "shuffle.circle.fill" }
        switch controller.repeatMode {
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

/// The queue gauge for what's on screen: how far through the queue
/// playback is, with the position in the middle — this device's queue, or
/// the speaker's while it plays from its queue. Also the mini player's
/// queue toggle on iPad.
struct PresentedQueueIconView: View {
    private var route: PlaybackRoute { .shared }

    @ScaledMetric(relativeTo: .caption2) private var iconSize: CGFloat = 24

    var body: some View {
        let controller = route.presented
        let position = controller.queuePosition
        VibeGaugeView(value: Double(position),
                      total: Double(controller.queueCount),
                      color: .primary,
                      lineWidth: 2)
        .overlay {
            // Four digits don't fit inside the gauge: past 999 the ring is
            // shown alone.
            if position < 1000 {
                Text(position, format: .number)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 4)
                    .allowsTightening(true)
                    .font(.caption2.monospacedDigit())
                    .contentTransition(.numericText())
            }
        }
        .animation(.spring, value: position)
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
                    HapticManager.shared.fireHaptic(.selection)
                    playback.setShuffle(!playback.isShuffled)
                } label: {
                    Label(playback.isShuffled ? "Shuffle On" : "Shuffle Off", systemImage: "shuffle")
                }
                .menuActionDismissBehavior(.disabled)
                .tint(playback.isShuffled ? .accent : .secondary)
                .disabled(!playback.isShuffled && playback.upNext.count < 2)

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

/// The backdrop for either source: a gradient of the cover's colours (see
/// `ArtworkMeshBackground`) under a thin material. One view for both, so a
/// change of source hands the gradient its new cover rather than building a
/// new backdrop; the old gradient stays until the new one is ready. Hidden
/// for a speaker in TV mode.
private struct PlayerBackdrop: View {
    /// The speaker on screen, or nil for this device.
    let group: GroupRoom?
    /// This device's display item.
    let content: PlayableContent?

    private var mesh: ArtworkMeshBackground {
        if let group {
            return ArtworkMeshBackground(group: group)
        }
        return ArtworkMeshBackground(content: content)
    }

    private var hasArtwork: Bool {
        if let group {
            return group.coordinatorRoom.track.artworkURL != nil
        }
        return content != nil
    }

    private var isTVMode: Bool {
        group?.TVMode ?? false
    }

    var body: some View {
        ZStack {
            mesh
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(hasArtwork ? 1 : 0)
            // Nothing queued on this device leaves the cover's own
            // background, with no material over it.
            if group != nil || content != nil {
                BlurView()
            }
        }
        .opacity(isTVMode ? 0 : 1)
        .animation(.smooth, value: isTVMode)
        .scaleEffect(1.3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
