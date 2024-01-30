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

    var body: some View {
        @Bindable var sonosService = sonosService

        VStack(alignment: .center) {
            ArtworkView(group: $group)
                .cornerRadius(12)
                .padding(.bottom, 24)
                .shadow(radius: 10)
                .frame(maxWidth: 500)

            if group.coordinatorRoom.track.TVMode {
                TVModeView()
            }
            else {
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

            if !group.coordinatorRoom.track.TVMode {
                playbackView()
                Spacer()
                mediaControlsView()
            }
            Spacer(minLength: 40)
            VStack {
                GroupVolumeControlView(group: $group, isExpanded: $isExpanded)
                    .padding(.bottom, 12)
                HStack(spacing: 0) {
                    Button {
                        router.presentedSheet  = .groupScreen(groupScreenViewModel: GroupScreenViewModel(groupCoordinatorID: group.coordinatorID, sonosService: sonosService), group: group)
                    } label: {
                        if group.TVMode {
                            Image(systemName: "tv.and.hifispeaker.fill")
                        } else {
                            Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                                .fontDesign(.rounded)
                                .font(.title3)
                        }

                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        router.presentedSheet = .search(group: group)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .fontDesign(.rounded)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    if group.rooms.count > 1 {
                        Spacer()
                        Button {
                            withAnimation(.bouncy(duration: 0.3)) {
                                isExpanded.toggle()
                            }
                        } label: {
                           Label("Room Volume", systemImage: "speaker.wave.2")
                                .labelStyle(.iconOnly)
                                .fontDesign(.rounded)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button {
                        router.presentedSheet = .queue(group: $group)
                    } label: {
                        Image(systemName: "list.dash")
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
                            .overlay(alignment: .topTrailing) {
                                if group.playMode.contains(.shuffle) {
                                    Image(systemName: "shuffle.circle.fill")
                                        .offset(x: 12, y: -12)
                                } else if group.playMode.contains(.repeatAll){
                                    Image(systemName: "repeat.circle.fill")
                                        .offset(x: 12, y: -12)
                                } else if group.playMode.contains(.repeatOne){
                                    Image(systemName: "repeat.1.circle.fill")
                                        .offset(x: 12, y: -12)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .dropDestinationPlay(on: group, now: false) { isTargeted in
                        if isTargeted {
                            HapticManager.shared.fireHaptic(.selection)
                        }
                        isHoveringOnQueueList = isTargeted
                    }
                }
                .frame(maxWidth: 300)
                .padding(.horizontal, 60)
            }
        }
        .frame(maxHeight: .infinity)
        .padding()
        .onAppear {
            guard !OSEnvironment.pad else { return }
            sonosService.selectedGroup = group
        }
        .onDisappear {
            guard !OSEnvironment.pad else { return }
            sonosService.selectedGroup = nil
        }
        .onChange(of: sonosService.selectedGroup) {
            if group != sonosService.selectedGroup, let selectedGroup = sonosService.selectedGroup {
                group = selectedGroup
            }
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
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                    }
                    .tint(.primary)
                }
            }
        }
        .dropDestinationPlay(on: group)
        .animation(.bouncy, value: group.playMode)
    }

    private func playbackView() -> some View {
        VStack(spacing: 0) {
            if !group.coordinatorRoom.track.duration.isZero {
                VibeSlider(value: $group.coordinatorRoom.track.playbackPosition, in: 0...group.coordinatorRoom.track.duration, step: 1000) { isEditing in
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(isEditing ? 0 : 1))
                        sonosService.isEditing = isEditing
                    }

                    if !isEditing {
                        Task {
                            await sonosService.seek(to: group.coordinatorRoom.track.playbackPosition, on: group)
                        }
                    }
                }
                .frame(maxWidth: 500, minHeight: 32)
                .foregroundStyle(.primary)
            }
            HStack {
                Text(group.coordinatorRoom.track.timestamp)
                Spacer()
                Text(group.coordinatorRoom.track.remainingTimestamp)
            }
            .frame(maxWidth: 500)
            .monospacedDigit()
            .font(.caption)
        }
        .fontDesign(.rounded)
        .frame(maxWidth: .infinity)
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
            }
            HStack {
                if let settings = Binding<TVSettings>($group.tvSettings) {
                    Toggle("Night Mode", systemImage: "moon.zzz", isOn: settings.nightMode)
                        .symbolVariant(settings.nightMode.wrappedValue ? .fill : .none)
                        .labelStyle(.iconOnly)
                        .contentShape(.circle)
                        .toggleStyle(.button)
                        .onChange(of: settings.nightMode.wrappedValue) { oldValue, newValue in
                            Task {
                                try? await sonosService.setNightMode(group.coordinatorRoom.ip, enabled: newValue)
                                group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                            }
                        }

                    Toggle("Dialog Mode", systemImage: "person.wave.2", isOn: settings.dialogLevel)
                        .symbolVariant(settings.dialogLevel.wrappedValue ? .fill : .none)
                        .labelStyle(.iconOnly)
                        .toggleStyle(.button)
                        .contentShape(.circle)
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
            track.artworkURL = await SonosService.shared.getArtwork(from: track)
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
