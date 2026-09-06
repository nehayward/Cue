import Nuke
import NukeUI
import SwiftUI
import Collections
import CloudStorage
import SonosKit
import VibesDS
import Kingfisher

struct TVPlayerView: View {
    @Environment(\.scenePhase) private var scenePhase

    @CloudStorage("com.cue.scenes") var scenes: [SonosScene] = []
    
    @Bindable var group: GroupRoom
    @Binding var showGroup: Bool
    @Binding var showSettings: Bool
    @ObservedObject var value: Test
    
    @State private var hideControls: Bool = false
    @State private var shouldFade: Bool = true
    @State private var currentImage: UIImage?
    @State private var volumeTask: Task<Void, Error>?
    @State private var selectionTrack: Task<Void, Never>?
    
    enum FocusedField: Equatable {
        case artwork, previous, next, play, volume, group, settings
    }
    
    @FocusState private var focusedField: FocusedField?

    class Test: ObservableObject {
        @Published var value: Double = 0
    }
    
    var body: some View {
        VStack {
            if group.TVMode {
                VStack {
                    Spacer()
                    Image(systemName: "tv")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 400, height: 400, alignment: .center)
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
                                    .frame(maxWidth: 600, maxHeight: 600)
                                    .background {
                                        RoundedRectangle(cornerRadius: 8)
                                            .foregroundStyle(.ultraThinMaterial)
                                    }
                                    .transition(.opacity)
                                    .tint(.primary)
                            }
                        }
                        .animation(.spring, value: group.isMuted)
                    TVModeView()
                    Spacer()
                }
                .transition(.opacity)
            } else {
                TVArtworkView(group: group, shouldFade: shouldFade, showBadge: true)
                    .frame(maxWidth: hideControls ? 800 : 600, maxHeight: nil)
                    .focusable()
                    .animation(.spring, value: hideControls)
                    .padding(.top, 80)
                    .padding(.bottom, 40)
                    .ignoresSafeArea(.all, edges: .top)
                    .focused($focusedField, equals: .artwork)
                    .scaleEffect(focusedField == .artwork ? 1.2 : 1)
                    .animation(.spring, value: focusedField)
                    .onTapGesture {
                        withAnimation(.spring) {
                            hideControls.toggle()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .focusSection()
                
                if let stationName = group.coordinatorRoom.track.metadata?.stationName {
                    Text(stationName)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fontDesign(.rounded)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1, reservesSpace: true)
                }
                MarqueeText(group.coordinatorRoom.track.song)
                    .bold()
                    .multilineTextAlignment(.center)
                    .fontDesign(.rounded)
                    .font(.title3)
                
                Text(group.coordinatorRoom.track.artist)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fontDesign(.rounded)
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1, reservesSpace: true)

                if !hideControls {
                    VStack {
                        playbackView()
                        mediaControlsView()
                            .defaultFocus($focusedField, .play)
                            .frame(maxWidth: .infinity)
                            .focusSection()
                    }
                    .transition(.opacity)
                }
            }
            if !hideControls {
                SliderView(value: value)
                    .focused($focusedField, equals: .volume)
                    .containerRelativeFrame(.horizontal) { size, _ in
                        size / 2
                    }
                    .frame(maxHeight: 20)
                    .focusSection()
                    .overlay {
                        VibeSliderTV(value: $group.groupVolume, showValue: true)
                            .containerRelativeFrame(.horizontal) { size, _ in
                                size / 2
                            }
                            .foregroundStyle(focusedField == .volume ? .primary : .secondary)
                    }
                    .task {
                        try? await Task.sleep(for: .milliseconds(400))
                        withAnimation {
                            value.value = group.groupVolume / 100
                        }
                    }
                    .onChange(of: value.value, initial: false) {
                        if focusedField != .volume || focusedField == nil { return }
                        print("----------")
                        print(group.groupVolume)
                        group.groupVolume = Double(value.value * 100)
                        updateVolume(volume: group.groupVolume)
                    }
                    .onChange(of: group.groupVolume) {
                        withAnimation {
                            value.value = group.groupVolume / 100
                        }
                    }
                    .onMoveCommand { direction in
                        guard ![.up, .down].contains(direction) else { return }
                        let value: Double = group.groupVolume + (direction == .left ? -2 : 2)
                        group.groupVolume = min(100, max(0, value))
                        self.value.value = group.groupVolume / 100
                        Task {
                            await SonosService.shared.setGroupVolume(ip: group.ip, volume: Int(value))
                        }
                    }
                    .id(group.coordinatorID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbarVisibility(focusedField != nil ? .hidden : .visible, for: .tabBar)
        .task(id: group) {
            group.isCrossfaded = await SonosService.shared.isCrossfaded(for: group)
            await SonosService.shared.getSleepTimer(group: group)
            group.coordinatorRoom.queue = OrderedSet(await SonosService.shared.getQueue(ip: group.coordinatorRoom.ip))
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task {
                    guard let track = await SonosService.shared.getTrack(ip: group.ip) else { return }
                    if group.coordinatorRoom.track.trackID == track.trackID {
                        group.coordinatorRoom.updatePlaybackPosition(track.playbackPosition)
                    }
                }
            }
        }
        .safeAreaPadding(.bottom)
        .background {
            if !group.TVMode {
                ZStack {
                    TVArtworkView(group: group, shouldFade: shouldFade, showBadge: false)
                        .ignoresSafeArea()
                        .saturation(1.3)
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(1.3)
                    Rectangle()
                        .foregroundStyle(.thinMaterial)
                        .scaleEffect(1.3)
                }
                .drawingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            }
        }
        .onChange(of: focusedField) {
            group.isEditingVolume = focusedField == .volume
        }
        .focusSection()
        .safeAreaInset(edge: .top) {
            ZStack {
                Button {
                    showSettings.toggle()
                } label: {
                    Label("Settings", systemImage: "gear")
                        .labelStyle(.iconOnly)
                }
                .focused($focusedField, equals: .settings)
                .buttonBorderShape(.circle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .leading], 60)
                .ignoresSafeArea()
                
                Text(group.nameWithCount)
                    .padding(.top, 24)
                    .ignoresSafeArea()
                    .opacity(focusedField == nil ? 0 : 1)
                    .animation(.default, value: focusedField)
                Button {
                    showGroup.toggle()
                } label: {
                    Label("Group", systemImage: "hifispeaker.arrow.forward.fill")
                        .labelStyle(.iconOnly)
                }
                .focused($focusedField, equals: .group)
                .buttonBorderShape(.circle)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding([.top, .trailing], 60)
                .ignoresSafeArea()
            }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea()
            .focusSection()
            .opacity(hideControls ? 0 : 1)
        }
        .onPlayPauseCommand {
            Task {
                if group.coordinatorRoom.isPlaying {
                    await SonosService.shared.pause(ip: group.coordinatorRoom.ip)
                } else {
                    await SonosService.shared.play(ip: group.coordinatorRoom.ip)
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(1000))
            shouldFade = true
        }
    }
    
    private func playbackView() -> some View {
        VStack(spacing: 0) {
            // Floored at one: a radio stream has no duration, and a
            // `ClosedRange` with its bounds inverted traps. See the same
            // guard on `LargePlayerView`'s scrubber.
            VibeSliderTV(value: $group.coordinatorRoom.playbackPosition, in: 0...max(group.coordinatorRoom.track.duration, 1), step: 1000, baseHeight: UIDevice.current.userInterfaceIdiom == .phone ? 16 : 24, showValue: false) { isEditing in
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(isEditing ? 0 : 1))
                    group.isEditingPlayback = isEditing
                }

                if !isEditing {
                    Task { @MainActor in
                        await SonosService.shared.seek(to: group.coordinatorRoom.playbackPosition, on: group)
                    }
                }
            }
            .frame(height: 40)
            .foregroundStyle(.primary)
            .disabled(!group.availableActions.contains(.scrubbable))

            HStack {
                let position = group.coordinatorRoom.playbackPosition
                let duration = group.coordinatorRoom.track.duration
                let timeRemaining = Duration.milliseconds(max(0, duration - position))
                if Duration.milliseconds(duration).components.seconds > (60 * 60) {
                    Text(Duration.milliseconds(position).formatted(.time(pattern: .hourMinuteSecond)))
                    Spacer()
                    Text("-") + Text(timeRemaining.formatted(.time(pattern: .hourMinuteSecond)))
                } else {
                    Text(Duration.milliseconds(position).formatted(.time(pattern: .minuteSecond)))
                    Spacer()
                    Text("-") + Text(timeRemaining.formatted(.time(pattern: .minuteSecond)))
                }
            }
            .monospacedDigit()
            .font(.caption)
            
        }
        .fontDesign(.rounded)
        .containerRelativeFrame(.horizontal, { size, axis in
            size / 2
        })
        .frame(height: 60)
    }
    
    private func mediaControlsView() -> some View {
        HStack {
            Button {
                selectionTrack?.cancel()
                selectionTrack = Task {
                    self.shouldFade = false
                    await SonosService.shared.previous(ip: group.coordinatorRoom.ip)
                    SonosService.shared.isEditing = true
                    try? await SonosService.shared.updateTrackInformation(for: [group])
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else {
                        return
                    }
                    SonosService.shared.isEditing = false
                    self.shouldFade = true
                }
            } label: {
                Image(systemName: "backward.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }
            .buttonBorderShape(.circle)
            .disabled(!group.availableActions.contains(.previous))
            .focused($focusedField, equals: .previous)
            Spacer()
            Button{
                Task {
                    if group.coordinatorRoom.isPlaying {
                        await SonosService.shared.pause(ip: group.coordinatorRoom.ip)
                    } else {
                        await SonosService.shared.play(ip: group.coordinatorRoom.ip)
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
            .buttonBorderShape(.circle)
            .id(group.coordinatorID)
            .focused($focusedField, equals: .play)
            Spacer()
            Button {
                selectionTrack?.cancel()
                selectionTrack = Task {
                    self.shouldFade = false
                    SonosService.shared.isEditing = true
                    await SonosService.shared.next(ip: group.coordinatorRoom.ip)
                    try? await SonosService.shared.updateTrackInformation(for: [group])
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else {
                        return
                    }
                    self.shouldFade = true
                    SonosService.shared.isEditing = false
                }
            } label: {
                Image(systemName: "forward.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            }
            .buttonBorderShape(.circle)
            .disabled(!group.availableActions.contains(.next))
            .focused($focusedField, equals: .next)
        }
        .frame(maxWidth: 300)
        .padding(.horizontal, 60)
    }

    
    private func TVModeView() -> some View {
        VStack(alignment: .center) {
            if let settings = group.tvSettings {
                Text(settings.audioInputFormat.description)
                    .multilineTextAlignment(.center)
                    .font(.title)
                    .bold()
            }
        }
        .fontDesign(.rounded)
    }
        
    private func updateVolume(volume: Double) {
        volumeTask?.cancel()
        volumeTask = Task {
            try Task.checkCancellation()
            await SonosService.shared.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(volume))
            if volume.isZero {
                try? await Task.sleep(for: .milliseconds(200))
                await SonosService.shared.snapShotGroup(ip: group.coordinatorRoom.ip)
            }
        }
    }
}


//#Preview("Theater Music") {
//    @Previewable @State var group: GroupRoom = .garagePlusTheater
//    @Previewable @State var showGroup: Bool = false
//    @Previewable @ObservedObject var value = TVPlayerView.Test()
//
//    TVPlayerView(group: group, showGroup: $showGroup, value: value)
//        .environment(SonosService.shared)
//        .task {
//            try? await SonosService.shared.load(useCache: true)
//            group = SonosService.shared.groups.first(where: { $0.ip == GroupRoom.theater.ip })!
//            print(group.nameWithCount)
//        }
//    
//}
