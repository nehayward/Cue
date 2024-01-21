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

    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()

    var body: some View {
        @Bindable var sonosService = sonosService

        VStack(alignment: .center) {
            ArtworkViewKing(group: $group)
                .cornerRadius(12)
                .padding(.bottom, 24)
                .shadow(radius: 10)
                .frame(maxWidth: 500)

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
                .padding(.bottom, isExpanded ? 20 : 40)
                .fontDesign(.rounded)

            if !group.tvMode {
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
                        Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                            .fontDesign(.rounded)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        router.presentedSheet = .search(group: group)
                    } label: {
                        Image(systemName: "magnifyingglass.circle.fill")
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
                           Label("Room Volume", systemImage: "speaker.wave.2.circle.fill")
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
                        Image(systemName: "list.number")
                            .fontDesign(.rounded)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

//                    if let musicServiceOpenURL = group.coordinatorRoom.track.safeURL {
                        // TODO: Add when flickering fixed
//                        Spacer()
//                        Menu {
//                            Link(destination: musicServiceOpenURL) {
//                                Label("Open in Spotify", image: .spotifyLogo)
//                            }
//                        } label: {
//                            Image(systemName: "ellipsis.circle.fill")
//                        }
//                        .tint(.primary)
//                    }
                }
                .frame(maxWidth: 300)
                .padding(.horizontal, 80)
            }
        }
        .frame(maxHeight: .infinity)
        .padding()
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(group.nameWithCount)
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
            Spacer()
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
            Spacer()
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

#Preview {
    NavigationStack {
        LargePlayerView(group: .constant(.garage))
            .environment(SonosService())
    }
}

#if DEBUG
#Preview("Group") {
    NavigationStack {
        LargePlayerView(group: .constant(.garagePlusTheater))
            .screenshot(name: "Player Screen")
            .environment(SonosService())
    }
    .colorScheme(.dark)
}

#Preview("Appstore Screens") {
    NavigationStack {
        LargePlayerView(group: .constant(.garage))
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
