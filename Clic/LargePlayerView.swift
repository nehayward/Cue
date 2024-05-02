import NukeUI
import SwiftUI
import SonosKit
import VibesDS

struct LargePlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router

    @Binding var group: GroupRoom

    @State var isExpanded: Bool = false
    @State private var isEditing: Bool = false
    @State private var volume: Double = 0
    @State private var isHoveringOnQueueList: Bool = false
    @State private var isCrossfaded: Bool = false

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
                Text(group.coordinatorRoom.track.name)
                    .bold()
                    .multilineTextAlignment(.center)
                    .fontDesign(.rounded)
            }

            Text(group.coordinatorRoom.track.artist)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.bottom, isExpanded ? 20 : 40)
                .fontDesign(.rounded)
                .frame(maxWidth: .infinity)
                .lineLimit(0, reservesSpace: true)

//            Text(group.coordinatorRoom.track.artworkURL?.absoluteString ?? "")

            if !group.TVMode {
                playbackView()
                Spacer()
                mediaControlsView()
            }
            Spacer(minLength: 40)
            VStack {
                GroupVolumeControlView(group: $group, isExpanded: $isExpanded)
                    .padding(.bottom, 12)
                if UIDevice.current.userInterfaceIdiom == .phone {
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
                            router.presentedSheet = .search(group: group)
                        } label: {
                            Image(systemName: "sparkle.magnifyingglass")
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
                    .padding(.horizontal, 60)
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
        }
        .onDisappear {
            sonosService.selectedGroup = nil
        }
        .background {
            ZStack {
                ArtworkView(group: $group)
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(2)
                    .blur(radius: 50)
                Rectangle()
                    .foregroundStyle(.thinMaterial)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(group.nameWithCount)
        .toolbar {
            if !group.TVMode {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let openInURL = group.coordinatorRoom.track.metadata?.openInURL {
                            if group.coordinatorRoom.track.musicService == .apple {
                                Link(destination: openInURL) {
                                    Label("Open in Apple Music…", systemImage: "apple.logo")
                                }
                            }
                            if group.coordinatorRoom.track.musicService == .spotify {
                                Link(destination: openInURL) {
                                    Label("Open in Spotify…", image: .spotifyLogo)
                                }
                            }
                        }
                        Link(destination: group.coordinatorRoom.track.nowPlayingURL) {
                            Label("Open in NowPlaying…", image: .nowPlayingAppIcon)
                        }
                        if [.spotify, .apple].contains(group.coordinatorRoom.track.musicService) {
                            Button {
                                router.sheet(to: .mediaDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
                            } label: {
                                Label("View Album", systemImage: "rectangle.stack.fill")
                            }

                            Button {
                                router.sheet(to: .artistDetail(content: group.coordinatorRoom.track.toPlayable, group: group))
                            } label: {
                                Label("View Artist", systemImage: "music.mic.circle.fill")
                            }

//                            let playable = group.coordinatorRoom.track.toPlayable
//                            ShareLink(item: playable)
                        }
                        ControlGroup {
                            Button {
                                setCrossfade()
                            } label: {
                                Label("Crossfade is \(isCrossfaded ? "On" : "Off")", systemImage: isCrossfaded ? "waveform" : "waveform.slash")
                            }
                            .menuActionDismissBehavior(.disabled)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .padding(.vertical)
                    }
                    .tint(.primary)
                }
            }
        }
        .dropDestinationPlay(on: group)
        .animation(.bouncy, value: group.playMode)
        .ignoresSafeArea(.keyboard)
        .task {
            group.isCrossfaded = await sonosService.isCrossfaded(for: group)
            if let isCrossfaded = group.isCrossfaded {
                self.isCrossfaded = isCrossfaded
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
                    Text(Duration.milliseconds(group.coordinatorRoom.track.playbackPosition).formatted(.time(pattern: .minuteSecond)))
                    Spacer()
                    Text("-") + Text(group.coordinatorRoom.track.timeRemaining.formatted(.time(pattern: .minuteSecond)))
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
                Image(systemName: "backward.end.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
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
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: []) 
            .id(group.coordinatorID)
            Spacer()
            Button {
                Task {
                    await HapticManager.shared.fireHaptic(.selection)
                    await sonosService.next(ip: group.coordinatorRoom.ip)
                }
            } label: {
                Image(systemName: "forward.end.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 300)
        .padding(.horizontal, 80)
    }

    private func TVModeView() -> some View {
        VStack(alignment: .center) {
            if let settings = group.tvSettings {
                Text(settings.audioInputFormat.description)
                    .bold()
            }
            HStack {
                if let settings = Binding<TVSettings>($group.tvSettings) {
                    Toggle("Night Mode", systemImage: "moon.zzz.fill", isOn: settings.nightMode)
                        .symbolRenderingMode(.hierarchical)
                        .labelStyle(.iconOnly)
                        .toggleStyle(.button)
                        .foregroundStyle(settings.nightMode.wrappedValue ? Color.accentColor : .secondary.opacity(0.8))
                        .onChange(of: settings.nightMode.wrappedValue) { oldValue, newValue in
                            Task {
                                try? await sonosService.setNightMode(group.coordinatorRoom.ip, enabled: newValue)
                                group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                            }
                        }

                    Toggle("Dialog Mode", systemImage: "person.wave.2.fill", isOn: settings.dialogLevel)
                        .symbolRenderingMode(.hierarchical)
                        .labelStyle(.iconOnly)
                        .toggleStyle(.button)
                        .foregroundStyle(settings.dialogLevel.wrappedValue ? Color.accentColor : .secondary.opacity(0.8))
                        .onChange(of: settings.dialogLevel.wrappedValue) { oldValue, newValue in
                            Task {
                                try? await sonosService.setDialogLevel(group.coordinatorRoom.ip, enabled: newValue)
                                group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                            }
                        }
                }
            }
        }
        .fontDesign(.rounded)
    }

    private func setCrossfade() {
        Task {
            isCrossfaded.toggle()
            await sonosService.setCrossfade(group: group, enabled: isCrossfaded)
        }
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
            let track = Track(trackID: "11C4y2Yz1XbHmaQwO06s9f", name: "Dance The Night", artist: "Dua Lipa", album: "Barbie The Album", musicService: .spotify, duration: 200000, playbackPosition: .zero, TVMode: false)
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
