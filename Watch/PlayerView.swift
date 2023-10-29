import Kingfisher
import SwiftUI
import SonosKit

struct PlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Popover.self) var popOver: Popover

    @Binding var group: GroupRoom
    @State private var isIdle: Bool = true
    @State private var showGroup: Bool = false
    @State private var volumeTask: Task<Void, Error>?
    @State private var artworkURL: URL?

    var body: some View {
        VStack {
            KFImage(artworkURL)
                .cacheMemoryOnly()
                .fade(duration: 0.2)
                .retry(DelayRetryStrategy(maxRetryCount: 2, retryInterval: .seconds(1)))
                .resizable()
                .aspectRatio(contentMode: .fit)
//            AsyncImage(
//                url: group.coordinatorRoom.track.artworkURL,
//                transaction: Transaction(animation: .snappy)
//            ) { phase in
//                switch phase {
//                case .success(let image):
//                    image
//                        .resizable()
//                        .aspectRatio(contentMode: .fit)
//                default:
//                    RoundedRectangle(cornerRadius: 12)
//                        .aspectRatio(contentMode: .fit)
//                        .foregroundStyle(.thinMaterial)
//                }
//            }
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
                withAnimation {
                    popOver.isShowing = !isIdle
                }
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
                .padding(.bottom)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .center) {
            if group.coordinatorRoom.track.name.isEmpty {
                Text("Nothing to play")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .multilineTextAlignment(.center)
            }
        }
        .background {
//            AsyncImage(
//                url: group.coordinatorRoom.track.artworkURL
//            ) { phase in
//                switch phase {
//                case .success(let image):
//                    image
//                        .resizable()
//                        .blur(radius: 20)
//                default:
//                    RoundedRectangle(cornerRadius: 12)
//                        .foregroundStyle(.thinMaterial)
//                }
//            }
//            .ignoresSafeArea()
//            .frame(maxWidth: .infinity, maxHeight: .infinity)
//            .overlay {
//                Rectangle()
//                    .foregroundStyle(.thinMaterial)
//                    .ignoresSafeArea()
//            }


        KFImage(artworkURL)
            .cacheMemoryOnly()
            .resizable()
            .blur(radius: 20)
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Rectangle()
                    .foregroundStyle(.thinMaterial)
                    .ignoresSafeArea()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showGroup.toggle()
                } label: {
                    Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                        .foregroundStyle(.foreground)
                }
            }
            ToolbarItemGroup (placement: .bottomBar) {
                Button {
                    Task {
                        await sonosService.previous(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                Button(action: {
                    Task {
                        if group.coordinatorRoom.isPlaying {
                            await sonosService.pause(ip: group.coordinatorRoom.ip)
                        } else {
                            await sonosService.play(ip: group.coordinatorRoom.ip)
                        }
                    }
                }, label: {
                    Gauge(
                        value: group.coordinatorRoom.track.playbackPosition,
                        in: 0...group.coordinatorRoom.track.duration,
                        label: {

                        },
                        currentValueLabel: {
                            Image(systemName: group.coordinatorRoom.isPlaying ? "pause.fill" : "play.fill")
                                .renderingMode(.template)
                                .foregroundColor(.primary)
                                .contentTransition(.symbolEffect(.automatic))
                        }
                    )
                    .tint(group.coordinatorRoom.track.playbackPosition.isZero ? .clear : .accentColor)
                    .gaugeStyle(.accessoryCircularCapacity)
                    .animation(.spring, value: group.coordinatorRoom.track.playbackPosition)
                })
                .controlSize(.large)
                .clipShape(Circle())
                Button {
                    Task {
                        await sonosService.next(ip: group.coordinatorRoom.ip)
                        try? await sonosService.fetch(useCache: true)
                    }
                } label: {
                    Image(systemName: "forward.end.fill")
                }
            }
        }
        .sheet(isPresented: $showGroup) {
            GroupScreen(group: $group, viewModel: GroupScreenViewModel(group: group))
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
        .navigationTitle(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
        .task {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }
                sonosService.monitor()
            let track = Track(trackID: "", name: "Dance The Night", artist: "Dua Lipa", album: "Barbie The Album", musicService: .airplay, duration: 60, playbackPosition: .zero)
            track.artworkURL = await sonosService.getArtwork(from: track)
            group.coordinatorRoom.track = track
        }
        .task(id: group.coordinatorRoom.track.name) {
            artworkURL = await sonosService.getArtwork(from: group.coordinatorRoom.track, size: 200)
        }
    }
}

#Preview {
    NavigationStack {
        PlayerView(group: .constant(.garage))
            .environment(SonosService())
            .environment(Popover())

    }
}
