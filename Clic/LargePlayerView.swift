import SwiftUI
import SonosKit
import VibesDS

struct LargePlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom
    @Binding var selected: Route?
    @State var isExpanded: Bool = false
    @State var showSearch = false
    
    @Binding var sheetDestination: SheetDestination?
    @State private var isEditing: Bool = false
    @State private var volume: Double = 0
    @State private var showQueue = false

    @State private var nextButtonTapped: Bool = false

    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()

    init(group: Binding<GroupRoom>, selected: Binding<Route?>, sheetDestination: Binding<SheetDestination?> = .constant(.none)) {
        self._group = group
        self._selected = selected
        self._sheetDestination = sheetDestination
    }

    var body: some View {
        VStack(alignment: .center) {
            //            ArtworkView(group: $group))
            ArtworkViewKing(group: $group)
                .cornerRadius(12)
                .padding(.bottom, 24)
                .shadow(radius: 10)

            if group.tvMode {
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
                .padding(.bottom, 80)
                .fontDesign(.rounded)

            if !group.tvMode {
                playbackView()
                mediaControlsView()
            }
        }
        .padding()
        .frame(maxHeight: .infinity)
        .task {
            guard OSEnvironment.isPreviews else { return }

            let track = Track(trackID: "", name: "Dance The Night", artist: "Dua Lipa", album: "Barbie The Album", musicService: .airplay, duration: 60, playbackPosition: .zero)
            track.artworkURL = await sonosService.getArtwork(from: track)
            group.rooms[0].track = track
            group.coordinatorRoom.track.duration = 200000
            Task {
                repeat {
                    try? await Task.sleep(for: .seconds(1)) // exception thrown when cancelled by SwiftUI when this view disappears.
                    group.rooms[0].track.playbackPosition += 1000

                } while (!Task.isCancelled)
            }

        }
        .sheet(isPresented: $showSearch, onDismiss: {
            selected?.search = false
        }) {
            ImprovedSearch(group: group)
        }
        .sheet(isPresented: $showQueue) {
            QueueScreen(group: $group)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: sonosService.selectedGroup) {
            if group != sonosService.selectedGroup, let selectedGroup = sonosService.selectedGroup {
                group = selectedGroup
            }
        }
        .onChange(of: selected, initial: true) {
            if let search = selected?.search {
                showSearch = search
            }
        }

        //        .toolbar(isExpanded ? .hidden : .automatic, for: .bottomBar)
        //        .toolbar(isExpanded ? .hidden : .automatic, for: .navigationBar)
        .background {
            ZStack {
                //                AsyncImage(
                //                    url: group.coordinatorRoom.track.artworkURL,
                //                    transaction: Transaction(animation: .snappy)
                //                ) { phase in
                //                    switch phase {
                //                    case .success(let image):
                //                        image
                //                            .resizable()
                //                            .aspectRatio(contentMode: .fill)
                //                            .scaleEffect(2)
                //                            .blur(radius: 50)
                //                    default:
                //                        RoundedRectangle(cornerRadius: 4)
                //                            .foregroundStyle(.thinMaterial)
                //                            .shadow(radius: 2)
                //                            .scaleEffect(3)
                //                    }
                ArtworkViewKing(group: $group)
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(2)
                    .blur(radius: 50)
                Rectangle()
                    .foregroundStyle(.thinMaterial)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                Rectangle()
                    .foregroundStyle(.ultraThinMaterial)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .opacity(isExpanded ? 1 : 0)
                    .onTapGesture {
                        withAnimation(.bouncy(duration: 0.3)) {
                            isExpanded = false
                        }
                    }
                VStack {
                    GroupVolumeControlView(group: $group, isExpanded: $isExpanded)
                    HStack(spacing: 60) {
                        Button {
                            sheetDestination = .groupScreen(groupScreenViewModel: GroupScreenViewModel(groupCoordinatorID: group.coordinatorID, sonosService: sonosService), group: group)
                        } label: {
                            Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                                .font(.body)
                        }
                        .fontDesign(.rounded)
                        .buttonStyle(.plain)
                        .font(.body)

                        Button {
                            showSearch.toggle()
                        } label: {
                            Image(systemName: "waveform.and.magnifyingglass")
                                .font(.body)
                        }
                        .fontDesign(.rounded)
                        .buttonStyle(.plain)
                        .font(.body)

                        Button {
                            showQueue.toggle()
                        } label: {
                            Image(systemName: "music.note.list")
                                .font(.body)
                        }
                        .fontDesign(.rounded)
                        .buttonStyle(.plain)
                        .font(.body)
                    }
                    .opacity(isExpanded ? 0 : 1)
                }
            }
        }
    }

    private func playbackView() -> some View {
        VStack(spacing: 0) {
            if !group.coordinatorRoom.track.duration.isZero {
                VibeSlider(value: $group.coordinatorRoom.track.playbackPosition, in: 0...group.coordinatorRoom.track.duration) { isEditing in
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
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    private func mediaControlsView() -> some View {
        HStack(spacing: 32) {
            Button {
                selectionFeedbackGenerator.selectionChanged()
                Task {
                    await sonosService.previous(ip: group.coordinatorRoom.ip)
                }
            } label: {
                Image(systemName: "backward.end.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Button{
                Task {
                    if group.coordinatorRoom.isPlaying {
                        await selectionFeedbackGenerator.selectionChanged()
                        await sonosService.pause(ip: group.coordinatorRoom.ip)
                    } else {
                        await selectionFeedbackGenerator.selectionChanged()
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

            Button {
                selectionFeedbackGenerator.selectionChanged()
                Task {
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
        .padding(.bottom, 60)
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

#Preview {
    NavigationStack {
        LargePlayerView(group: .constant(.garage), selected: .constant(nil))
            .environment(SonosService())
            .onAppear {
                let thumbImage = UIImage()
                UISlider.appearance().setThumbImage(thumbImage, for: .normal)
            }
    }
}

#if DEBUG
#Preview("Group") {
    NavigationStack {
        LargePlayerView(group: .constant(.garagePlusTheater), selected: .constant(nil))
            .screenshot(name: "Player Screen")
            .environment(SonosService())
            .onAppear {
                let thumbImage = UIImage()
                UISlider.appearance().setThumbImage(thumbImage, for: .normal)
            }
    }
    .colorScheme(.dark)
}

#Preview("Appstore Screens") {
    NavigationStack {
        LargePlayerView(group: .constant(.garage), selected: .constant(nil))
            .screenshot(name: "Player Screen")
            .colorScheme(.dark)
            .environment(SonosService())
            .onAppear {
                let thumbImage = UIImage()
                UISlider.appearance().setThumbImage(thumbImage, for: .normal)
            }
    }
}
#endif
