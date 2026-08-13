import SwiftUI
import SonosKit
import MusicSearchKit
import VibesDS
import Defaults

struct LargePlayerView: View {
    @AppStorage(AppStorageKeys.showArtworkOnly) private var showArtworkOnly: Bool = false
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router

    // Take an ID, not a `GroupRoom`. The live group is resolved from
    // `sonosService.groups` at body time so a topology refresh (which
    // replaces every GroupRoom instance via `self.groups = newGroup`) can't
    // leave this view's captured reference orphaned. Async .task blocks
    // also re-resolve at start to avoid acting on a stale instance.
    let coordinatorID: String

    // ContainerLargePlayerView sets this false on iPad/Mac (regular width)
    // and hosts the ellipsis menu itself, trailing its search/browse/queue
    // toolbar buttons.
    var showsEllipsisToolbarItem: Bool = true

    @State private var isEditing: Bool = false
    @State private var shouldFade: Bool = false
    @State private var isFavorite: Bool?

    @State private var scrubbingTask: Task<Void, Error>?
    @State private var isArtworkVisible: Bool = true
    @State private var showSleepTimerCancelConfirmation: Bool = false

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

    // Resolved fresh on every read so topology refreshes (which replace
    // every GroupRoom instance) can't orphan us. `.task` closures should
    // re-resolve via `self.group` inside the closure rather than relying
    // on the body-time unwrap.
    private var group: GroupRoom? {
        sonosService.groups.first(where: { $0.coordinatorID == coordinatorID })
    }

    // `shouldFade` covers skips made from this screen's own transport buttons.
    // The ⌘← / ⌘→ menu commands live in `Commands` and can't reach that state,
    // so they open an equivalent window on the router; either one suppresses
    // the crossfade.
    private var artworkShouldFade: Bool {
        shouldFade && !router.isSkippingTrack
    }

    /// Toolbar subtitle: lowest battery percentage among the group's
    /// battery-powered rooms. Nil for AC-only groups (hides the subtitle).
    private var lowestBatteryPercent: Int? {
        group?.lowestBattery.map { Int($0.percentage.rounded()) }
    }

    var body: some View {
        if let group {
            VStack(alignment: .center) {
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
                                        .containerRelativeFrame(.horizontal) { size, axis in
                                            size * 0.25
                                        }
                                        .frame(maxWidth: isMacCatalystOrPad ? 600 : 400, maxHeight: isMacCatalystOrPad ? 400 : 400)
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
                        TVModeView(group: group)
                        Spacer()
                    }
                    .transition(.opacity)
                } else {
                    ArtworkView(group: group, isDraggable: true, showBadge: true, shouldFade: artworkShouldFade)
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
                    SongTitleButton(group: group)
                    ArtistButton(group: group, showArtworkOnly: showArtworkOnly)
                    if !showArtworkOnly {
                        VStack {
                            PlaybackView(group: group)
                            PlayerMediaControlsView(group: group, shouldFade: $shouldFade)
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
                        
                        BottomToolbarView(group: group)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.interactiveSpring, value: showArtworkOnly)
            #if !targetEnvironment(macCatalyst)
            .onDisappear {
                sonosService.selectedGroup = nil
            }
            #endif
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(group.nameWithCount)
                            .bold()
                            .fontDesign(.rounded)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .tint(.primary)
                        // Subtitle for groups containing at least one
                        // battery-powered speaker (Roam / Move). Shows the
                        // lowest battery in the group since that's the one
                        // at risk first — matches how multi-speaker stereo
                        // pairs experience runtime.
                        if let percent = lowestBatteryPercent {
                            Text("\(percent)%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
    #if !os(visionOS)
                    .overlay {
                        Menu {
                            ForEach(group.rooms) { room in
                                Text(room.name)
                                    .bold()
                                    .fontDesign(.rounded)
                            }
                        } label: {
                            Text(group.nameWithCount)
                                .hidden()
                                .contentShape(Rectangle())
                        }
                    }
    #endif
                }
                
                if let date = group.coordinatorRoom.sleepTimer, date > Date.now {
                    if #available(iOS 26.0, visionOS 26.0, *) {
                        ToolbarItem {
                            Button {
                                showSleepTimerCancelConfirmation = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "moon.zzz.fill")
                                        .foregroundStyle(Color.primary.gradient, .indigo)
                                    Text(date, style: .timer)
                                        .contentTransition(.numericText(countsDown: true))
                                        .animation(.spring, value: date)
                                        .monospacedDigit()
                                        .bold()
                                }
                            }
                            .buttonStyle(.plain)
                            .modifier(RefreshOnForegroundModifier())
                            .confirmationDialog(
                                "Cancel Sleep Timer",
                                isPresented: $showSleepTimerCancelConfirmation,
                                titleVisibility: .visible
                            ) {
                                Button("Cancel Sleep Timer", role: .destructive) {
                                    Task {
                                        await sonosService.stopSleepTimer(group: group)
                                    }
                                }
                                Button("Keep Timer", role: .cancel) { }
                            } message: {
                                Text("Stop the sleep timer on \(group.coordinatorRoom.name)?")
                            }
                        }
                        #if !os(visionOS)
                        .sharedBackgroundVisibility(.hidden)
                        #endif
                    } else {
                        ToolbarItem {
                            Button {
                                showSleepTimerCancelConfirmation = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "moon.zzz.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Color.primary.gradient, .indigo)
                                    Text(date, style: .timer)
                                        .contentTransition(.numericText(countsDown: true))
                                        .animation(.spring, value: date)
                                        .monospacedDigit()
                                        .bold()
                                }
                            }
                            .buttonStyle(.plain)
                            .modifier(RefreshOnForegroundModifier())
                            .confirmationDialog(
                                "Cancel Sleep Timer",
                                isPresented: $showSleepTimerCancelConfirmation,
                                titleVisibility: .visible
                            ) {
                                Button("Cancel Sleep Timer", role: .destructive) {
                                    Task {
                                        await sonosService.stopSleepTimer(group: group)
                                    }
                                }
                                Button("Keep Timer", role: .cancel) { }
                            } message: {
                                Text("Stop the sleep timer on \(group.coordinatorRoom.name)?")
                            }
                        }
                    }
                }
               
                #if !os(visionOS)
                if #available(iOS 26.0, visionOS 26.0, *) {
                    ToolbarSpacer(.fixed)
                }
                #endif
                ToolbarItem {
                    LikeButtonView(group: group)
                }
                if showsEllipsisToolbarItem {
                    #if !os(visionOS)
                    if #available(iOS 26.0, visionOS 26.0, *) {
                        ToolbarSpacer(.fixed)
                    }
                    #endif
                    ToolbarItem {
                        MenuInfoView(group: group, showArtworkOnly: $showArtworkOnly)
                            .tint(.primary)
                            .modifier(RefreshOnForegroundModifier())
                    }
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .dropDestinationPlay(on: group)
            // .task closures re-resolve via `self.group` at start. The body
            // shadowed `group` is the body-time instance; if SonosService
            // replaced `groups` since then it'd be orphaned.
            .task(id: coordinatorID) {
                guard let group = self.group else { return }
                // Re-points the `.viewing` listener; the registry closes the
                // previous group's socket unless another listener (the Now
                // Playing session) still needs it. No `disconnectAll()` here —
                // that used to take the Lock Screen's socket down with it.
                await sonosService.getTrackAudioInformation(ip: group.ip, playerID: group.coordinatorID, groupID: group.id)
                group.isCrossfaded = await sonosService.isCrossfaded(for: group)
                await sonosService.getSleepTimer(group: group)
            }
            .task(id: coordinatorID) {
                guard let group = self.group else { return }
                sonosService.selectedGroup = group
                try? await sonosService.updateTrackInformation(for: [group])
            }
            .modifier(ScenePhaseSyncModifier(coordinatorID: coordinatorID))
            .environment(AlertService.shared)
            .padding(.horizontal, 32)
            .safeAreaPadding(.bottom)
            .ignoresSafeArea(.keyboard)
            .background {
                BackgroundViewCatalyst(group: group, shouldFade: artworkShouldFade)
            }
            .hardwareVolumeControl(group: group)
            .task(id: coordinatorID) {
                guard let group = self.group else { return }
                let awaitedPlayMode = await sonosService.playMode(ip: group.ip)
                if group.playMode != awaitedPlayMode {
                    group.playMode = awaitedPlayMode
                }
                try? await Task.sleep(for: .milliseconds(400))
                shouldFade = true
            }
            // Was `.onChange(of: group)` — GroupRoom.== includes track content
            // so it fired on every song change and reset the crossfade. We only
            // care about identity (speaker switch).
            .onChange(of: coordinatorID) {
                shouldFade = false
            }
        }
    }
}

fileprivate struct ScenePhaseSyncModifier: ViewModifier {
    @Environment(SonosService.self) private var sonosService: SonosService
    @Environment(\.scenePhase) private var scenePhase
    // Resolve fresh by id on each scenePhase change — capturing a `GroupRoom`
    // here would survive across topology updates and act on an orphaned
    // instance after a foreground/background cycle, which was the suspected
    // cause of stale track info on device after wake.
    let coordinatorID: String

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) {
                guard let group = sonosService.groups.first(where: { $0.coordinatorID == coordinatorID }) else { return }
                if scenePhase == .active {
                    Task {
                        try? await sonosService.updateTrackInformation(for: [group])
                    }

                    Task {
                        await sonosService.getTrackAudioInformation(ip: group.ip, playerID: group.coordinatorID, groupID: group.id)
                    }
                } else if scenePhase == .background {
                    Task {
                        await sonosService.stopViewing()
                    }
                }
            }
    }
}

fileprivate struct RefreshOnForegroundModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var refreshID = UUID()

    func body(content: Content) -> some View {
        content
            .id(refreshID)
            .onChange(of: scenePhase) {
                if horizontalSizeClass != .compact, UIDevice.current.userInterfaceIdiom == .pad {
                    refreshID = UUID()
                }
            }
    }
}

fileprivate struct SongTitleButton: View {
    @Environment(Router.self) private var router: Router
    @Bindable var group: GroupRoom

    @State private var isHovering: Bool = false

    private var isSupported: Bool { group.coordinatorRoom.track.musicService.supportsViewArtistAlbum }

    var body: some View {
        Button {
            guard isSupported else { return }
            HapticManager.shared.fireHaptic(.buttonPress)
            router.sheet(to: .mediaDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
        } label: {
            MarqueeText(group.coordinatorRoom.track.song)
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

fileprivate struct ArtistButton: View {
    @Environment(Router.self) private var router: Router

    let group: GroupRoom
    let showArtworkOnly: Bool

    @State private var isHovering: Bool = false

    private var isSupported: Bool { group.coordinatorRoom.track.musicService.supportsViewArtistAlbum }

    var body: some View {
        Button {
            guard isSupported else { return }
            HapticManager.shared.fireHaptic(.buttonPress)
            router.sheet(to: .artistDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
        } label: {
            Text(group.coordinatorRoom.track.artist)
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

fileprivate struct PlaybackView: View {
    @Environment(SonosService.self) private var sonosService: SonosService
    @Bindable var group: GroupRoom

    var body: some View {
        VStack(spacing: 0) {
            VibeSlider(value: $group.coordinatorRoom.playbackPosition, in: 0...group.coordinatorRoom.track.duration, step: 100, baseHeight: UIDevice.current.userInterfaceIdiom == .phone ? 16 : 24) { isEditing in
                sonosService.isEditing = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(isEditing ? 0 : 1))
                    group.isEditingPlayback = isEditing
                }

                if !isEditing {
                    Task { @MainActor in
                        await sonosService.seek(to: group.coordinatorRoom.playbackPosition, on: group)
                        sonosService.isEditing = false
                    }
                }
            }
            .frame(maxWidth: 500)
            .frame(height: 40)
            .foregroundStyle(.primary)
            .disabled(!group.availableActions.contains(.scrubbable))

            HStack {
                let duration = Duration.milliseconds(group.coordinatorRoom.track.duration)
                let position = Duration.milliseconds(group.coordinatorRoom.playbackPosition)
                let timeRemaining = Duration.milliseconds(max(0, group.coordinatorRoom.track.duration - group.coordinatorRoom.playbackPosition))

                let usesHourFormat = duration.components.seconds > 3600
                let pattern: Duration.TimeFormatStyle.Pattern = usesHourFormat ? .hourMinuteSecond : .minuteSecond

                Text(position.formatted(.time(pattern: pattern)))
                    .contentTransition(.identity)
                Spacer()
                AudioInfoView(group: group)
                    .frame(height: 12)
                    .contentTransition(.identity)
                Spacer()
                Text("-\(timeRemaining.formatted(.time(pattern: pattern)))")
                    .contentTransition(.identity)
            }
            .frame(maxWidth: 500)
            .monospacedDigit()
            .font(.caption)
        }
        .fontDesign(.rounded)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .opacity(group.coordinatorRoom.track.duration.isZero ? 0 : 1)
        .animation(.spring, value: group.audioQuality)
    }
}

fileprivate struct PlayerMediaControlsView: View {
    @Environment(SonosService.self) private var sonosService: SonosService
    @Bindable var group: GroupRoom
    @Binding var shouldFade: Bool

    @State private var selectionTrack: Task<Void, Never>?

    var body: some View {
        HStack {
            Button {
                selectionTrack?.cancel()
                selectionTrack = Task {
                    HapticManager.shared.fireHaptic(.selection)
                    shouldFade = false
                    // No refresh here: this screen holds a metadata socket open
                    // (see `getTrackAudioInformation` above), and the speaker
                    // pushes the new item as soon as it has one. Reading it
                    // ourselves the instant the command returned only ever
                    // fetched the outgoing track anyway.
                    await sonosService.previous(ip: group.coordinatorRoom.ip)
                    // Hold the no-fade window open until well past that push.
                    // `ArtworkView` snapshots `shouldFade` when the URL changes,
                    // so the window has to still be open when the new track
                    // lands or a deliberate skip crossfades instead of snapping.
                    // It used to close 200 ms after a refresh this button ran
                    // itself; the socket's lands later than that.
                    try? await Task.sleep(for: .milliseconds(1500))
                    guard !Task.isCancelled else {
                        return
                    }
                    shouldFade = true
                }
            } label: {
                Image(systemName: "backward.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.liveActivity)
            .disabled(!group.availableActions.contains(.previous) && group.playbackService != .queue)

            Spacer()
            Button{
                Task {
                    if group.coordinatorRoom.isPlaying {
                        HapticManager.shared.fireHaptic(.selection)
                        await sonosService.pause(ip: group.coordinatorRoom.ip)
                    } else {
                        HapticManager.shared.fireHaptic(.selection)
                        await sonosService.play(ip: group.coordinatorRoom.ip)
                    }
                }
            } label: {
                Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                    .resizable()
                    .scaledToFit()
                    .contentTransition(.symbolEffect(.automatic))
                    .symbolEffect(.pulse, isActive: group.coordinatorRoom.isTransitioning)
                    .frame(width: 32, height: 32)

            }
            .buttonStyle(.liveActivity)
            #if DEBUG && !targetEnvironment(macCatalyst)
            .keyboardShortcut(.space, modifiers: [])
            .id(group.coordinatorID)
            #endif

            Spacer()
            Button {
                selectionTrack?.cancel()
                selectionTrack = Task {
                    HapticManager.shared.fireHaptic(.selection)
                    group.coordinatorRoom.playbackPosition = 0
                    shouldFade = false
                    // Left to the socket — twin of the previous button above,
                    // including the no-fade window. Holding `isEditing` across a
                    // refresh here also parked the pulse in 500 ms sleeps, so
                    // the fallback was slower than doing nothing.
                    await sonosService.next(ip: group.coordinatorRoom.ip)
                    try? await Task.sleep(for: .milliseconds(1500))
                    guard !Task.isCancelled else {
                        return
                    }
                    shouldFade = true
                }
            } label: {
                Image(systemName: "forward.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.liveActivity)
            .disabled(!group.availableActions.contains(.next))
        }
        .frame(maxWidth: 300)
        .padding(.horizontal, 60)
    }
}

fileprivate struct BottomToolbarView: View {
    @Environment(Router.self) private var router: Router
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var group: GroupRoom

    @State private var scaleAnimation: Double = -40
    @State private var isHoveringOnQueueList: Bool = false

    var body: some View {
        @Bindable var router = router

        if UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact {
            HStack(spacing: 0) {
                Button {
                    router.presentedSheet = .groupScreen(group: group)
                } label: {
                    GroupIconView()
                }
                .buttonStyle(.plain)
                .imageScale(.large)

                if group.rooms.count > 1 {
                    Spacer()
                    Button {
                        router.volumePopover = .volumeControlsScreen(groupID: group.coordinatorID)
                    } label: {
                        Label("Room Volume", systemImage: "speaker.wave.2.fill")
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .fontDesign(.rounded)
                    }
                    .buttonStyle(.plain)
                    .imageScale(.large)
                    .withPopoverDestinations(popoverDestination: $router.volumePopover)
                }
                Spacer()
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    router.presentedSheet = .search(group: group)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .symbolRenderingMode(.hierarchical)
                        .fontDesign(.rounded)
                }
                .buttonStyle(.plain)
                .imageScale(.large)
                Spacer()
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    router.sheet(to: .browse(group: group))
                } label: {
                    Image("home.fill")
                        .fontDesign(.rounded)
                }
                .buttonStyle(.plain)
                .imageScale(.large)

                Spacer()
                Button {
                    router.presentedSheet = .queue(group: group)
                } label: {
                    QueueIconView(group: group)
                        .fontDesign(.rounded)
                        .font(.title3)
                        .foregroundColor(isHoveringOnQueueList ? .accentColor : nil)
                        .overlay(alignment: .topTrailing) {
                            if isHoveringOnQueueList {
                                Image(systemName: "plus.circle.fill")
                                    .offset(x: 12, y: -18)
                                    .transition(.scale)
                                    .foregroundStyle(.green.gradient)
                            }
                        }
                        .overlay {
                            if let lastQueuedItem = QueueManager.shared.lastQueuedItem {
                                ContentArtworkView(content: lastQueuedItem.playableContent, showMusicSource: false)
                                    .scaleEffect(scaleAnimation == -40 ? 1.5 : 0.2)
                                    .offset(y: scaleAnimation)
                                    .opacity(scaleAnimation == -40 ? 1 : 0)
                                    .onAppear {
                                        withAnimation(.easeInOut(duration: 0.5).delay(2)) {
                                            scaleAnimation = 0
                                        } completion: {
                                            print("Done")
                                            scaleAnimation = -40
                                            QueueManager.shared.lastQueuedItem = nil
                                        }
                                    }
                            }
                        }
                }
                .buttonStyle(.plain)
                .imageScale(.large)
                .overlay(alignment: .topTrailing) {
                    if group.playMode.contains(.shuffle) {
                        Image(systemName: "shuffle.circle.fill")
                            .symbolRenderingMode(.multicolor)
                            .foregroundStyle(.black.secondary)
                            .offset(x: 10, y: -10)
                    } else if group.playMode.contains(.repeatAll){
                        Image(systemName: "repeat.circle.fill")
                            .symbolRenderingMode(.multicolor)
                            .foregroundStyle(.black.secondary)
                            .offset(x: 10, y: -10)
                    } else if group.playMode.contains(.repeatOne){
                        Image(systemName: "repeat.1.circle.fill")
                            .symbolRenderingMode(.multicolor)
                            .foregroundStyle(.black.secondary)
                            .offset(x: 10, y: -10)
                    }
                }
                .dropDestinationPlay(on: group, position: .next) { isTargeted in
                    if isTargeted {
                        HapticManager.shared.fireHaptic(.selection)
                    }
                    isHoveringOnQueueList = isTargeted
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 28)
            .frame(maxWidth: 500)
            .glassToolbar()
        } else {
            HStack {
                if group.rooms.count > 1 {
                    Button {
                        router.volumePopover = .volumeControlsScreen(groupID: group.coordinatorID)
                    } label: {
                        Label("Room Volume", systemImage: "speaker.wave.2.fill")
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 24, height: 24)
                            .labelStyle(.iconOnly)
                            .fontDesign(.rounded)
                    }
                    .buttonBorderShape(.circle)
                    .glassButton()
                    .withPopoverDestinations(popoverDestination: $router.volumePopover)
                    .help("Speaker Control")
                }


                Button {
                    router.popover = .groupScreen(group: group)
                } label: {
                    Label {
                        Text("Group")
                    } icon: {
                        GroupIconView()
                            .frame(width: 24, height: 24)
                            .labelStyle(.iconOnly)
                            .fontDesign(.rounded)
                    }
                    .labelStyle(.iconOnly)
                }
                .buttonBorderShape(.circle)
                .glassButton()
                .withPopoverDestinations(popoverDestination: $router.popover)
                .help("Group Speakers")
            }
        }
    }
}

fileprivate struct TVModeView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Bindable var group: GroupRoom
    
    var body: some View {
        VStack(alignment: .center) {
            if let settings = group.tvSettings {
                Text(settings.audioInputFormat.description)
                    .multilineTextAlignment(.center)
                    .font(.title)
                    .bold()
            }
            HStack(spacing: 24) {
                if let settings = Binding<TVSettings>($group.tvSettings) {
                    Button {
                        Task {
                            try? await sonosService.setNightMode(group.coordinatorRoom.ip, enabled: !settings.nightMode.wrappedValue)
                            group.tvSettings = try? await sonosService.getTVSettings(group: group)
                        }
                    } label: {
                        Label("Night Mode", systemImage: "moon.zzz.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .foregroundStyle(settings.nightMode.wrappedValue ? .accent : .secondary.opacity(0.8))
                            .frame(width: 40, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(settings.nightMode.wrappedValue ? .accent : nil)
                    .animation(.spring, value: settings.nightMode.wrappedValue)

                    MuteButton(group: group)

                    if group.isArcUltra {
                        SpeechEnhancementMenu(group: group, showLabel: true)
                    } else {
                        Button {
                            Task {
                                try? await sonosService.setDialogLevel(group.coordinatorRoom.ip, enabled: !settings.dialogLevel.wrappedValue)
                                group.tvSettings = try? await sonosService.getTVSettings(group: group)
                            }
                        } label: {
                            Label("Dialog Mode", systemImage: "person.wave.2.fill")
                                .font(.title)
                                .symbolRenderingMode(.hierarchical)
                                .labelStyle(.iconOnly)
                                .foregroundStyle(settings.dialogLevel.wrappedValue ? .accent : .secondary.opacity(0.8))
                                .frame(width: 40, height: 36)
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(settings.dialogLevel.wrappedValue ? .accent : .secondary.opacity(0.8))
                        .tint(settings.dialogLevel.wrappedValue ? .accent : nil)
                        .animation(.spring, value: settings.dialogLevel.wrappedValue)
                    }
                }
            }

        }
        .fontDesign(.rounded)
    }
}

fileprivate struct BackgroundView: View {
    var group: GroupRoom
    var shouldFade: Bool
    
    var body: some View {
        ZStack {
            ArtworkView(group: group, isDraggable: false, showBadge: false, shouldFade: shouldFade, isBackground: true)
                .saturation(1.3)
                .aspectRatio(contentMode: .fill)
                .scaleEffect(1.3)
                .opacity(group.coordinatorRoom.track.artworkURL == nil ? 0 : 1)
            Rectangle()
                .foregroundStyle(.thinMaterial)
                .scaleEffect(1.3)
                .opacity(group.TVMode ? 0 : 1)
        }
        .backgroundExtension26()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

fileprivate struct BackgroundViewCatalyst: View {
    var group: GroupRoom
    var shouldFade: Bool
    
    var body: some View {
        ZStack {
            ArtworkView(group: group, isDraggable: false, showBadge: false, shouldFade: shouldFade, isBackground: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .saturation(1.3)
                .opacity(group.coordinatorRoom.track.artworkURL == nil ? 0 : 1)
                .blur(radius: 80)
            BlurView()
        }
        .opacity(group.TVMode ? 0 : 1)
        .animation(.smooth, value: group.TVMode)
        .scaleEffect(1.3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}


fileprivate struct TVContainer: View {
    @State var group: GroupRoom = .theater
    var body: some View {
        NavigationStack {
            LargePlayerView(coordinatorID: group.coordinatorID)
                .environment(SonosService.shared)
                .environment(Router())
                .task { SonosService.shared.groups = [group] }
        }
        .colorScheme(.dark)
    }
}

fileprivate struct DuaLipaContainer: View {
    @State var group: GroupRoom = GroupRoom(id: "RINCON_48A6B80D8FB401400:2447655112",
                                            coordinatorID: Room.theater.id,
                                            rooms: [.theater],
                                            coordinatorRoom: .theater,
                                            tvSettings: TVSettings(nightMode: true, dialogLevel: false, audioInputFormat: .dolbyStereo))

    var body: some View {
        NavigationStack {
            LargePlayerView(coordinatorID: group.coordinatorID)
                .withEnvironments()
                .environment(Router())
        }
        .colorScheme(.dark)
        .task {
            SonosService.shared.groups = [group]
            // https://open.spotify.com/track/11C4y2Yz1XbHmaQwO06s9f
            var track = Track(trackID: "11C4y2Yz1XbHmaQwO06s9f", name: "Dance The Night", artist: "Dua Lipa", album: "Barbie The Album", musicService: .spotify, duration: 200000, playbackPosition: .zero)
            track.downloadedArtworkURL = await SonosService.shared.getArtwork(from: track)
            group.coordinatorRoom.track = track
            group.coordinatorRoom.track.duration = 200000
            group.groupVolume = 10
        }
    }
}

#Preview("Theater") {
    TVContainer()
}

#Preview("Theater Music") {
    @Previewable @State var coordinatorID: String = GroupRoom.garagePlusTheater.coordinatorID
    NavigationStack {
        LargePlayerView(coordinatorID: coordinatorID)
            .environment(Router.main)
            .task {
                try? await SonosService.shared.load(useCache: true)
                if let group = SonosService.shared.groups.first(where: { $0.ip == GroupRoom.theater.ip }) {
                    coordinatorID = group.coordinatorID
                    print(group.nameWithCount)
                }
            }
    }
    .withEnvironments()
}


#Preview("Dua Lipa") {
    DuaLipaContainer()
}

struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemThinMaterial // Use this!
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: style))
        return blurView
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        uiView.effect = UIBlurEffect(style: style)
        CATransaction.commit()
    }
}
