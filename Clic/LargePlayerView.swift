import SwiftUI
import SonosKit

struct LargePlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom
    @Binding var selected: String?

    @State private var isEditing: Bool = false
    @State private var volume: Double = 0
    @State private var showGroup = false
    @State private var showSearch = false
    @State private var showQueue = false

    @State private var isExpanded: Bool = false
    @State private var nextButtonTapped: Bool = false

    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()

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
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }

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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Image(systemName: "hifispeaker.fill")
                    Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
                }
                .fontDesign(.rounded)
                .bold()
            }
            ToolbarItem(placement: .bottomBar) {
                HStack(spacing: 60) {
                    Button {
                        showGroup.toggle()
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
            }
        }
        .sheet(isPresented: $showGroup) {
            GroupScreen(group: $group, viewModel: GroupScreenViewModel(group: group))
        }
        .sheet(isPresented: $showSearch) {
            //            SearchScreen(group: group)

            ImprovedSearch(group: group)
        }
        .sheet(isPresented: $showQueue) {
            QueueScreen(group: group)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: sonosService.selectedGroup) {
            if group != sonosService.selectedGroup, let selectedGroup = sonosService.selectedGroup {
                group = selectedGroup
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
                GroupVolumeControlView(group: $group, isExpanded: $isExpanded)
            }
        }
    }

    private func playbackView() -> some View {
        VStack {
            if !group.coordinatorRoom.track.duration.isZero {
                ProgressView(value: group.coordinatorRoom.track.playbackPosition, total: group.coordinatorRoom.track.duration)
                    .tint(.primary)
                    .progressViewStyle(.linear)

            }
            HStack {
                Text(group.coordinatorRoom.track.timestamp)
                Spacer()
                Text(group.coordinatorRoom.track.remainingTimestamp)
            }
            .monospacedDigit()
            .font(.caption)
        }
        .fontDesign(.rounded)
        .padding(.bottom, 24)
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
    }
}
