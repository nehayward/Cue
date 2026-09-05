import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI
import VibesDS

/// Full-screen view of what's playing locally on this device, opened from the
/// tab bar accessory.
///
/// The same screen as `LargePlayerView`, driven by `LocalPlaybackService`
/// instead of a `GroupRoom`. A header names the device the way the Sonos
/// player names its group, with the sleep timer beside it; below it the
/// artwork, the album line, the title and the artist (each opening its
/// detail), the scrubber with the audio-quality badge, the transport, the
/// volume row with its steppers, and the glass bar — on a phone the route
/// picker, like, Up Next and the menu; wider, route, search, browse and Up
/// Next with like and the menu up in the header. All state is the
/// `PlayableContent` the search returned, so nothing here needs a lookup.
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

    private var playback: LocalPlaybackService { .shared }

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

    /// A phone, or an iPad window squeezed to one: the like button and the
    /// menu move down into the bottom bar.
    private var isCompact: Bool {
        UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact
    }

    /// The header's title: this device, where the Sonos player has its
    /// group's name.
    private var deviceName: String { UIDevice.current.name }

    var body: some View {
        // No `NavigationStack`: the cover's root stays the view the zoom
        // transition morphs out of the mini player — wrapping it in a stack
        // lost the zoom. The bar is drawn as `header` instead.
        VStack(alignment: .center) {
            header

            if let item = playback.nowPlaying {
                ContentArtworkView(content: item, showMusicSource: true, preferredSize: 600, cornerRadius: 8, isDraggable: true)
                    .shadow(radius: 2)
                    .padding(.bottom, showArtworkOnly ? 0 : 12)
                    .frame(minWidth: 0, maxWidth: showArtworkOnly ? .infinity : (isMacCatalystOrPad ? 800 : 500), minHeight: 0, maxHeight: showArtworkOnly ? .infinity : (isMacCatalystOrPad ? .infinity : 400))
                    .padding(.top, showArtworkOnly ? 100 : nil)
                    .onGeometryChange(for: Bool.self) { proxy in
                        proxy.size.height >= 100
                    } action: { isArtworkVisible = $0 }
                    .opacity(isArtworkVisible ? 1 : 0)
                    .animation(.interactiveSpring, value: isArtworkVisible)

                // The album line, in the slot `LargePlayerView` gives the
                // container. Fixed height so the layout doesn't shift between
                // tracks that have one and tracks that don't.
                LocalAlbumButton(item: item)
                    .frame(height: 12)
                LocalSongTitleButton(item: item)
                LocalArtistButton(item: item, showArtworkOnly: showArtworkOnly)

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

                        LocalBottomToolbarView(item: item, showQueue: $showQueue, showArtworkOnly: $showArtworkOnly)
                    }
                    .transition(.opacity)
                }
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
        // Presented from in here rather than the main window: its sheets
        // hang off the tab content underneath this cover and would come up
        // behind it.
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
        .withAlert()
        // The same trailing panel the main window uses where there's room —
        // it shows and hides in place, and the artwork reflows around it —
        // and a half-height sheet on a phone, where a side panel would only
        // squeeze both halves.
        .queuePanel(isPresented: $showQueue) {
            QueueNextUpView()
        }
        .background {
            PlayerBackgroundView(content: playback.nowPlaying)
        }
        // Anything dropped on the screen plays here, the way a drop on the
        // Sonos player plays on that group.
        .dropDestinationPlayOnDevice()
        .fontDesign(.rounded)
        .environment(router)
        .withEnvironments()
    }

    /// Stands in for the Sonos player's navigation bar: the device and its
    /// service in the middle, the sleep timer beside them, and where there
    /// is room the like button and the menu. A phone keeps those two in the
    /// bottom bar so the top stays clear.
    private var header: some View {
        ZStack {
            VStack(spacing: 0) {
                Text(deviceName)
                    .bold()
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                // Where the Sonos player shows a battery, this shows the
                // service the track is coming from.
                if let item = playback.nowPlaying {
                    Text(item.content.service.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .contentTransition(.identity)
                }
            }

            HStack(spacing: 12) {
#if targetEnvironment(macCatalyst)
                // A phone drags the cover back into the mini player; a Mac
                // has no such gesture, so it gets the chevron.
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "chevron.down")
                        .labelStyle(.iconOnly)
                        .frame(width: 24, height: 24)
                }
                .buttonBorderShape(.circle)
                .glassButton()
                .help("Close")
#endif
                Spacer()

                if let item = playback.nowPlaying {
                    if let date = playback.sleepTimerEndDate, date > Date.now {
                        sleepTimerChip {
                            Text(date, style: .timer)
                                .contentTransition(.numericText(countsDown: true))
                                .animation(.spring, value: date)
                                .monospacedDigit()
                                .bold()
                        }
                    } else if playback.sleepsAtEndOfTrack {
                        sleepTimerChip {
                            Text("End of Song")
                                .bold()
                        }
                    }

                    if !isCompact {
                        if item.content.service.supportsFavoriteTrack {
                            LikeButtonView(content: item)
                                .glassButton()
                        }
                        LocalPlayerMenuView(item: item, showArtworkOnly: $showArtworkOnly)
                            .buttonBorderShape(.circle)
                            .glassButton()
                            .tint(.primary)
                    }
                }
            }
        }
        .frame(minHeight: 44)
    }

    /// The sleep timer chip: the moon, whatever `detail` says about when,
    /// and a confirmation to call it off — as on the Sonos player.
    private func sleepTimerChip<Detail: View>(@ViewBuilder detail: () -> Detail) -> some View {
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
            Button("Cancel Sleep Timer", role: .destructive) {
                playback.cancelSleepTimer()
            }
            Button("Keep Timer", role: .cancel) { }
        } message: {
            Text("Stop the sleep timer on \(deviceName)?")
        }
    }
}

// MARK: - Album, title, artist

/// The album line: a tap opens the album, as the container line on the
/// Sonos player does. Services with no album screen keep the text but not
/// the tap.
private struct LocalAlbumButton: View {
    @Environment(Router.self) private var router: Router

    let item: PlayableContent

    private var isSupported: Bool { item.content.service.supportsViewArtistAlbum }

    var body: some View {
        Button {
            guard isSupported else { return }
            HapticManager.shared.fireHaptic(.buttonPress)
            router.sheet(to: .mediaDetail(content: item, group: nil))
        } label: {
            Text(item.metadata?.album ?? "")
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

    @State private var isHovering: Bool = false

    private var isSupported: Bool { item.content.service.supportsViewArtistAlbum }

    var body: some View {
        Button {
            guard isSupported else { return }
            HapticManager.shared.fireHaptic(.buttonPress)
            router.sheet(to: .mediaDetail(content: item, group: nil))
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
    let showArtworkOnly: Bool

    @State private var isHovering: Bool = false

    private var isSupported: Bool { item.content.service.supportsViewArtistAlbum }

    var body: some View {
        Button {
            guard isSupported else { return }
            HapticManager.shared.fireHaptic(.buttonPress)
            router.sheet(to: .artistDetail(content: item, group: nil))
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

    var body: some View {
        HStack {
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
        .frame(maxWidth: 300)
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

/// The glass row under the volume, mirroring `LargePlayerView.BottomToolbarView`.
/// On a phone: the route picker where the Sonos player has its group button,
/// the like button, the Up Next toggle with its queue gauge, and the menu —
/// the bar carries what the navigation bar would, so the top stays clear.
/// Where there's room the like button and the menu sit in the header, and
/// the row is glass circles for route, search, browse and Up Next.
private struct LocalBottomToolbarView: View {
    @Environment(Router.self) private var router: Router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let item: PlayableContent
    @Binding var showQueue: Bool
    @Binding var showArtworkOnly: Bool

    @State private var isHoveringOnQueueList: Bool = false

    private var playback: LocalPlaybackService { .shared }

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact {
            HStack(spacing: 0) {
                PlaybackRouteButton()
                    .buttonStyle(.plain)
                    .imageScale(.large)

                if item.content.service.supportsFavoriteTrack {
                    Spacer()
                    LikeButtonView(content: item)
                        .buttonStyle(.plain)
                        .imageScale(.large)
                }

                Spacer()
                queueButton
                    .buttonStyle(.plain)
                    .imageScale(.large)

                Spacer()
                LocalPlayerMenuView(item: item, showArtworkOnly: $showArtworkOnly)
                    .buttonStyle(.plain)
                    .imageScale(.large)
                    .tint(.primary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .frame(maxWidth: 500)
            .glassToolbar()
        } else {
            HStack {
                PlaybackRouteButton()
                    .buttonBorderShape(.circle)
                    .glassButton()
                    .help("Play On")

                searchButton
                    .buttonBorderShape(.circle)
                    .glassButton()
                    .help("Search")

                browseButton
                    .buttonBorderShape(.circle)
                    .glassButton()
                    .help("Browse")

                queueButton
                    .buttonBorderShape(.circle)
                    .accentGlassButton(active: showQueue)
                    .help("Up Next")
            }
        }
    }


    private var searchButton: some View {
        Button {
            HapticManager.shared.fireHaptic(.buttonPress)
            router.sheet(to: .search(group: nil))
        } label: {
            Label("Search", systemImage: "magnifyingglass")
                .symbolRenderingMode(.hierarchical)
                .labelStyle(.iconOnly)
                .fontDesign(.rounded)
        }
    }

    private var browseButton: some View {
        Button {
            HapticManager.shared.fireHaptic(.buttonPress)
            router.sheet(to: .browse(group: nil))
        } label: {
            Label("Browse", image: "home.fill")
                .labelStyle(.iconOnly)
                .fontDesign(.rounded)
        }
    }

    private var queueButton: some View {
        Button {
            HapticManager.shared.fireHaptic(.selection)
            withAnimation {
                showQueue.toggle()
            }
        } label: {
            LocalQueueIconView()
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
        .disabled(playback.queue.isEmpty)
        .overlay(alignment: .topTrailing) {
            switch playback.repeatMode {
            case .all:
                Image(systemName: "repeat.circle.fill")
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(.black.secondary)
                    .offset(x: 10, y: -10)
            case .one:
                Image(systemName: "repeat.1.circle.fill")
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(.black.secondary)
                    .offset(x: 10, y: -10)
            case .off:
                EmptyView()
            }
        }
        // A drop on the queue button plays next, as on the Sonos player.
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
    @Environment(\.dismiss) private var dismiss

    let item: PlayableContent
    @Binding var showArtworkOnly: Bool

    private var playback: LocalPlaybackService { .shared }

    var body: some View {
        Menu {
            OpenInServiceView(item: item)
            if item.content.service.supportsViewArtistAlbum {
                Button {
                    router.sheet(to: .mediaDetail(content: item, group: nil))
                } label: {
                    Label("View Album", systemImage: "smallcircle.circle.fill")
                }

                Button {
                    router.sheet(to: .artistDetail(content: item, group: nil))
                } label: {
                    Label("View Artist", systemImage: "music.mic")
                }
            }

            Divider()
            AddToLastPlaylistButton(itemToAdd: item)
            Button {
                router.sheet(to: .addToPlaylist(content: item))
            } label: {
                Label("Add to Playlist…", systemImage: "text.badge.plus")
            }
            Divider()

            // The other direction from the Sonos player's "This Device":
            // a file in the Files folder is the one thing no speaker can take.
            if !item.content.service.playsOnDeviceOnly {
                Button {
                    router.sheet(to: .playContent(content: item))
                } label: {
                    Label("Play on Speaker…", systemImage: "hifispeaker.arrow.forward.fill")
                }
            }

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

            Divider()
            Button {
                playback.stop()
                dismiss()
            } label: {
                Label("Stop", systemImage: "stop.fill")
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
