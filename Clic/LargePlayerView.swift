import NukeUI
import SwiftUI
import Collections
import SonosKit
import VibesDS
import Glur

struct LargePlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @Binding var group: GroupRoom

    @State var isExpanded: Bool = false
    @State private var isEditing: Bool = false
    @State private var volume: Double = 0
    @State private var isHoveringOnQueueList: Bool = false
    @State private var refreshID = UUID()

    var body: some View {
        @Bindable var sonosService = sonosService

        VStack(alignment: .center) {
            ArtworkView(group: $group)
                .cornerRadius(12)
                .padding(.bottom, 24)
                .draggable(group.coordinatorRoom.track.toPlayable)
                .shadow(radius: 10)
                .frame(maxWidth: 500)

            if group.TVMode {
                TVModeView()
            }  else {
                if let stationName = group.coordinatorRoom.track.metadata?.stationName {
                    Text(stationName)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fontDesign(.rounded)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1, reservesSpace: true)
                }

                Text(group.coordinatorRoom.track.song)
                    .lineLimit(1, reservesSpace: true)
                    .bold()
                    .multilineTextAlignment(.center)
                    .fontDesign(.rounded)

                Text(group.coordinatorRoom.track.artist)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, isExpanded ? 20 : 40)
                    .fontDesign(.rounded)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1, reservesSpace: true)

                playbackView()
                Spacer()
                mediaControlsView()
            }

            Spacer(minLength: 40)
            VStack {
                GroupVolumeControlView(group: $group, isExpanded: $isExpanded)
                    .padding(.bottom, 12)
                if UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact  {
                    HStack(spacing: 0) {
                        Button {
                            router.presentedSheet = .groupScreen(group: group)
                        } label: {
                            if group.TVMode {
                                Image(systemName: "tv.and.hifispeaker.fill")
                                    .fontDesign(.rounded)
                            } else {
                                Image(systemName: "hifispeaker")
                                    .symbolRenderingMode(.hierarchical)
                                    .fontDesign(.rounded)
                            }
                        }
                        .buttonStyle(.plain)
                        .imageScale(.large)
                        Spacer()
                        Button {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            router.sheet(to: .browse(group: group))
                        } label: {
                            Image(systemName: "music.note.house")
                                .fontDesign(.rounded)
                        }
                        .buttonStyle(.plain)
                        .imageScale(.large)
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

                        if group.rooms.count > 1 {
                            Spacer()
                            Button {
                                withAnimation(.bouncy(duration: 0.3)) {
                                    isExpanded.toggle()
                                }
                            } label: {
                                Label("Room Volume", systemImage: "speaker.wave.2.circle")
                                    .symbolRenderingMode(.hierarchical)
                                    .labelStyle(.iconOnly)
                                    .fontDesign(.rounded)
                            }
                            .buttonStyle(.plain)
                            .imageScale(.large)
                        }
                        Spacer()
                        Button {
                            router.presentedSheet = .queue(group: $group)
                        } label: {
                            Group {
                                if group.playbackService == .queue {
                                    Image(systemName: "list.bullet")
                                } else {
                                    Image("custom.list.bullet.slash")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentTransition(.symbolEffect)
                            .fontDesign(.rounded)
                            .font(.title3)
                            .foregroundColor(isHoveringOnQueueList ? .accentColor : nil)
                            .overlay(alignment: .topTrailing) {
                                if isHoveringOnQueueList {
                                    Image(systemName: "plus.circle.fill")
                                        .offset(x: 12, y: -18)
                                        .transition(.scale)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .imageScale(.large)
                        .dropDestinationPlay(on: group, now: false) { isTargeted in
                            if isTargeted {
                                HapticManager.shared.fireHaptic(.selection)
                            }
                            isHoveringOnQueueList = isTargeted
                        }
                        .overlay(alignment: .topTrailing) {
                            if group.playMode.contains(.shuffle) {
                                Image(systemName: "shuffle.circle.fill")
                                    .symbolRenderingMode(.multicolor)
                                    .foregroundStyle(.background)
                                    .offset(x: 8, y: -8)
                                    .shadow(radius: 2)
                                    .environment(\.colorScheme, .dark)
                            } else if group.playMode.contains(.repeatAll){
                                Image(systemName: "repeat.circle.fill")
                                    .symbolRenderingMode(.multicolor)
                                    .foregroundStyle(.background)
                                    .offset(x: 8, y: -8)
                                    .shadow(radius: 2)
                                    .environment(\.colorScheme, .dark)
                            } else if group.playMode.contains(.repeatOne){
                                Image(systemName: "repeat.1.circle.fill")
                                    .symbolRenderingMode(.multicolor)
                                    .foregroundStyle(.background)
                                    .offset(x: 8, y: -8)
                                    .shadow(radius: 2)
                                    .environment(\.colorScheme, .dark)
                            }
                        }
                    }
                    .frame(maxWidth: 300)
                    .padding(.horizontal, 38)
                } else {
                    if group.rooms.count > 1 {
                        Button {
                            withAnimation(.bouncy(duration: 0.3)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Label("Room Volume", systemImage: "speaker.wave.2.circle")
                                .symbolRenderingMode(.hierarchical)
                                .labelStyle(.iconOnly)
                                .fontDesign(.rounded)
                        }
                        .frame(maxWidth: 300)
                        .padding(.horizontal, 60)
                        .padding(.bottom, 24)
                        .buttonStyle(.plain)
                        .imageScale(.large)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .padding()
        .onChange(of: group, initial: true) {
            sonosService.selectedGroup = group
            if group.rooms.count < 2 {
                isExpanded = false
            }
        }
        .onDisappear {
            sonosService.selectedGroup = nil
        }
        .background {
            ArtworkView(group: $group)
                .saturation(1.2)
                .aspectRatio(contentMode: .fill)
                .scaleEffect(1.3)
                .blur(radius: 60)
                .overlay {
                    Rectangle()
                        .foregroundStyle(.thinMaterial)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                }
                .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(group.nameWithCount)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let date = group.coordinatorRoom.sleepTimer, date > Date.now {
                    Text(date, style: .timer)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.spring, value: date)
                        .monospacedDigit()
                        .bold()
                        .id(refreshID)
                }
                MenuInfoView(group: group)
                    .tint(.primary)
                    .id(refreshID)
            }
        }
        .dropDestinationPlay(on: group)
        .animation(.bouncy, value: group.playMode)
        .ignoresSafeArea(.keyboard)
        .task(id: group) {
            group.isCrossfaded = await sonosService.isCrossfaded(for: group)
            await sonosService.getSleepTimer(group: group)
            group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.coordinatorRoom.ip))
        }
        .onChange(of: scenePhase) {
            if horizontalSizeClass != .compact, UIDevice.current.userInterfaceIdiom == .pad {
                refreshID = UUID()
            }
        }
    }

    private func playbackView() -> some View {
        VStack {
            if !group.coordinatorRoom.track.duration.isZero {
                VibeSlider(value: $group.coordinatorRoom.track.playbackPosition, in: 0...group.coordinatorRoom.track.duration, step: 1000, baseHeight: UIDevice.current.userInterfaceIdiom == .phone ? 16 : 24) { isEditing in
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(isEditing ? 0 : 1))
                        sonosService.isEditing = isEditing
                    }

                    if !isEditing {
                        Task { @MainActor in
                            await sonosService.seek(to: group.coordinatorRoom.track.playbackPosition, on: group)
                        }
                    }
                }
                .frame(maxWidth: 500)
                .frame(height: 40)
                .foregroundStyle(.primary)
                .disabled(!group.availableActions.contains(.scrubbable))

                HStack {
                    if Duration.milliseconds(group.coordinatorRoom.track.duration).components.seconds > (60 * 60) {
                        Text(Duration.milliseconds(group.coordinatorRoom.track.playbackPosition).formatted(.time(pattern: .hourMinuteSecond)))
                        Spacer()
                        Text("-") + Text(group.coordinatorRoom.track.timeRemaining.formatted(.time(pattern: .hourMinuteSecond)))
                    } else {
                        Text(Duration.milliseconds(group.coordinatorRoom.track.playbackPosition).formatted(.time(pattern: .minuteSecond)))
                        Spacer()
                        Text("-") + Text(group.coordinatorRoom.track.timeRemaining.formatted(.time(pattern: .minuteSecond)))
                    }
                }
                .frame(maxWidth: 500)
                .monospacedDigit()
                .font(.caption)
            }
        }
        .fontDesign(.rounded)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
    }

    private func mediaControlsView() -> some View {
        HStack {
            Button {
                Task {
                    await HapticManager.shared.fireHaptic(.selection)
                    await sonosService.previous(ip: group.coordinatorRoom.ip)
                }
            } label: {
                Image(systemName: "backward.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.liveActivity)
            .disabled(!group.availableActions.contains(.previous))
            
            Spacer()
            Button{
                Task {
                    if group.coordinatorRoom.isPlaying {
                        await HapticManager.shared.fireHaptic(.selection)
                        await sonosService.pause(ip: group.coordinatorRoom.ip)
                    } else {
                        await HapticManager.shared.fireHaptic(.selection)
                        await sonosService.play(ip: group.coordinatorRoom.ip)
                    }
                }
            } label: {
                Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                    .resizable()
                    .scaledToFit()
                    .contentTransition(.symbolEffect(.automatic))
                    .frame(width: 32, height: 32)

            }
            .buttonStyle(.liveActivity)
            .keyboardShortcut(.space, modifiers: []) 
            .id(group.coordinatorID)

            Spacer()
            Button {
                Task {
                    await HapticManager.shared.fireHaptic(.selection)
                    await sonosService.next(ip: group.coordinatorRoom.ip)
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

    private func TVModeView() -> some View {
        VStack(alignment: .center) {
            if let settings = group.tvSettings {
                Text(settings.audioInputFormat.description)
                    .bold()
            }
            HStack {
                if let settings = Binding<TVSettings>($group.tvSettings) {
                    Button {
                        Task {
                            try? await sonosService.setNightMode(group.coordinatorRoom.ip, enabled: !settings.nightMode.wrappedValue)
                            group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                        }
                    } label: {
                        Label("Night Mode", systemImage: "moon.zzz.fill")
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .toggleStyle(.button)
                            .foregroundStyle(settings.nightMode.wrappedValue ? .accent : .secondary.opacity(0.8))
                    }
                    .buttonStyle(.bordered)
                    .tint(settings.nightMode.wrappedValue ? .accent : nil)
                    .animation(.spring, value: settings.nightMode.wrappedValue)

                    Button {
                        Task {
                            try? await sonosService.setDialogLevel(group.coordinatorRoom.ip, enabled:  !settings.dialogLevel.wrappedValue)
                            group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                        }
                    } label: {
                        Label("Dialog Mode", systemImage: "person.wave.2.fill")
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .toggleStyle(.button)
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(settings.dialogLevel.wrappedValue ? .accent : .secondary.opacity(0.8))
                    .tint(settings.dialogLevel.wrappedValue ? .accent : nil)
                    .animation(.spring, value: settings.dialogLevel.wrappedValue)
                }
            }
        }
        .fontDesign(.rounded)
    }
}


fileprivate struct TVContainer: View {
    @State var group: GroupRoom = .theater
    var body: some View {
        NavigationStack {
            LargePlayerView(group: $group)
                .environment(SonosService.shared)
                .environment(Router())
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
            LargePlayerView(group: $group)
                .environment(SonosService.shared)
                .environment(Router())
        }
        .colorScheme(.dark)
        .task {
            // https://open.spotify.com/track/11C4y2Yz1XbHmaQwO06s9f
            let track = Track(trackID: "11C4y2Yz1XbHmaQwO06s9f", name: "Dance The Night", artist: "Dua Lipa", album: "Barbie The Album", musicService: .spotify, duration: 200000, playbackPosition: .zero)
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

#Preview("Dua Lipa") {
    DuaLipaContainer()
}
