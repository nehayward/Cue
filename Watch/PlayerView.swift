import NukeUI
import SwiftUI
import WatchKit
import MusicSearchKit
import SonosKit

struct PlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Popover.self) var popOver: Popover

    @Binding var group: GroupRoom
    @State private var isIdle: Bool = true
    @State private var showGroup: Bool = false
    @State private var volumeTask: Task<Void, Error>?

    var body: some View {
        VStack(spacing: 4) {
            LazyImage(url: group.coordinatorRoom.track.artworkURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                } else if state.isLoading {
                    Rectangle()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.ultraThinMaterial)
                        .shadow(radius: 2)
                        .transition(.opacity)
                } else {
                    Rectangle()
                        .foregroundStyle(.accent.gradient.secondary)
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            if group.coordinatorRoom.track.artworkURL == nil {
                                Image(systemName: "music.note")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.regularMaterial)
                                    .frame(width: 42, height: 42)
                            }
                        }
                }
            }
//            // MARK: For Screenshots
//            #if DEBUG
//            .overlay {
//                Rectangle()
//                    .foregroundStyle(.regularMaterial)
//            }
//            #endif
            .overlay(alignment: .bottomTrailing) {
                group.coordinatorRoom.track.musicService.icon
                    .frame(width: 10, height: 10)
                    .padding([.trailing, .bottom], 4)
                    .shadow(radius: 10)
            }
            .cornerRadius(12)
            .shadow(radius: 10)
            .focusable()
            .digitalCrownRotation(detent: $group.groupVolume,
                                  from: 0,
                                  through: 100,
                                  by: 2,
                                  sensitivity: .low,
                                  isContinuous: false,
                                  isHapticFeedbackEnabled: true,
                                  onChange: { crownEvent in
                isIdle = false
                popOver.isShowing = !isIdle
                popOver.text = String(format: "%.0f", group.groupVolume)
            }, onIdle: {
                isIdle = true
                withAnimation {
                    popOver.isShowing = !isIdle
                }
            })
            Text(group.coordinatorRoom.track.name)
                .bold()
                .lineLimit(1)
            Text(group.coordinatorRoom.track.artist)
                .foregroundColor(.secondary)
                .lineLimit(1)
            HStack {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    Task {
                        await sonosService.previous(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .controlSize(.mini)
                .clipShape(Circle())
                Button(action: {
                    Task {
                        if group.coordinatorRoom.isPlaying {
                            WKInterfaceDevice.current().play(.stop)
                            await sonosService.pause(ip: group.coordinatorRoom.ip)
                        } else {
                            WKInterfaceDevice.current().play(.start)
                            await sonosService.play(ip: group.coordinatorRoom.ip)
                        }
                    }
                }, label: {
                    ZStack {
                        Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                            .renderingMode(.template)
                            .foregroundColor(.primary)
                            .contentTransition(.symbolEffect(.automatic))
                        Gauge(
                            value: group.coordinatorRoom.track.playbackPosition,
                            in: 0...group.coordinatorRoom.track.duration,
                            label: {

                            },
                            currentValueLabel: {
                                EmptyView()
                            }
                        )
                        .tint(group.coordinatorRoom.isPlaying ? .accentColor : Color.secondary)
                        .gaugeStyle(.accessoryCircularCapacity)
                        .animation(.spring, value: group.coordinatorRoom.track.playbackPosition)
                        .frame(width: 24, height: 24)
                    }
                })
                .clipShape(Circle())
                .frame(width: 48, height: 48)
                Button {
                    WKInterfaceDevice.current().play(.click)
                    Task {
                        await sonosService.next(ip: group.coordinatorRoom.ip)
                        try? await sonosService.fetch(useCache: true)
                    }
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .controlSize(.mini)
                .clipShape(Circle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .ignoresSafeArea(edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showGroup.toggle()
                } label: {
                    Image(systemName: "hifispeaker.fill")
                        .fontDesign(.rounded)
                        .foregroundStyle(.foreground)
                }
            }
        }
        .sheet(isPresented: $showGroup) {
            GroupScreen(coordinatorID: group.coordinatorID)
        }
        .onChange(of: group.groupVolume) {
            if isIdle { return }
            volumeTask?.cancel()
            volumeTask = Task {
                await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(group.groupVolume))
            }
        }
        .onChange(of: sonosService.selectedGroup) {
            if group != sonosService.selectedGroup, let selectedGroup = sonosService.selectedGroup {
                group = selectedGroup
            }
        }
//        .onChange(of: group) {
//            print("Refreshed", group)
//            sonosService.selectedGroup = group
//            // MARK: Refresh
//            Task {
//                guard let track = await sonosService.getTrack(ip: group.coordinatorRoom.ip) else { return }
//                let previousArtwork = group.coordinatorRoom.track.artworkURL
//                group.coordinatorRoom.track = track
//                if previousArtwork != nil {
//                    group.coordinatorRoom.track.artworkURL = previousArtwork
//                }
//                guard let artworkURL = await sonosService.getArtwork(from: track, size: 100) else {
//                    return
//                }
//                if artworkURL != previousArtwork {
//                    group.coordinatorRoom.track.artworkURL = artworkURL
//                }
//            }
//        }
        .navigationTitle(group.nameWithCount)
        .task {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }
                sonosService.monitor()
            let track = Track(trackID: "", name: "Dance The Night", artist: "Dua Lipa", album: "Barbie The Album", musicService: .airplay, duration: 60, playbackPosition: .zero)
            track.downloadedArtworkURL = await sonosService.getArtwork(from: track)
            group.coordinatorRoom.track = track
        }
        .animation(.spring, value: popOver.isShowing)
        .animation(.spring, value: group.coordinatorRoom.track.artworkURL)
    }
}

#Preview {
    NavigationStack {
        PlayerView(group: .constant(.garage))
            .environment(SonosService())
            .environment(Popover())

    }
}
