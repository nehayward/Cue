import Kingfisher
import SwiftUI
import SonosKit

struct PlayerView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Popover.self) var popOver: Popover

    @Bindable var group: GroupRoom
    @State var isIdle: Bool = true
    @State var showGroup: Bool = false
    @State var volume: Double  = 0

    var body: some View {
        VStack {
            KFImage(group.coordinatorRoom.track.artworkURL)
                .cacheMemoryOnly()
                .fade(duration: 0.25)
                .onProgress { receivedSize, totalSize in  }
                .onSuccess { result in  }
                .onFailure { error in }
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
                volume = group.groupVolume
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
        KFImage(group.coordinatorRoom.track.artworkURL)
            .cacheMemoryOnly()
            .fade(duration: 0.25)
            .onProgress { receivedSize, totalSize in  }
            .onSuccess { result in  }
            .onFailure { error in }
            .resizable()
            .blur(radius: 20)
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .transaction { transaction in
                    transaction.animation = nil
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
                                .foregroundStyle(.tint, .thickMaterial)
                                .contentTransition(.symbolEffect(.automatic))
                        }
                    )
                    .tint(Color.primary.gradient)
                    .gaugeStyle(.accessoryCircularCapacity)
                    .animation(.linear, value: group.coordinatorRoom.track.playbackPosition)
                })
                .buttonStyle(.plain)
                .scaleEffect(0.8)
                .transaction { transaction in
                    transaction.animation = nil
                }
                Button {
                    Task {
                        await sonosService.next(ip: group.coordinatorRoom.ip)
                        try? await sonosService.fetch()
                    }
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
        .sheet(isPresented: $showGroup) {
            GroupScreen(roomGroup: group, viewModel: GroupScreenViewModel(group: group))
        }
        .onChange(of: volume) {
            Task {
                await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(volume))
            }
        }
        .onChange(of: group) {
            print("Refreshed", group)
            sonosService.selectedGroup = group
            // MARK: Refresh
            Task {
                guard let track = await sonosService.getTrack(ip: group.coordinatorRoom.ip) else { return }
                let previousArtwork = group.coordinatorRoom.track.artworkURL
                group.coordinatorRoom.track = track
                if previousArtwork != nil {
                    group.coordinatorRoom.track.artworkURL = previousArtwork
                }
                guard let artworkURL = await sonosService.getArtwork(from: track, size: 100) else {
                    return
                }
                if artworkURL != previousArtwork {
                    group.coordinatorRoom.track.artworkURL = artworkURL
                }
            }
        }
        .navigationTitle(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
        .task {
            print("Set Volume")
            volume = group.groupVolume

            print("Fetching Track")
            let previousArtwork = group.coordinatorRoom.track.artworkURL
            if previousArtwork != nil {
                group.coordinatorRoom.track.artworkURL = previousArtwork
            }
            guard let artworkURL = await sonosService.getArtwork(from: group.coordinatorRoom.track, size: 100) else {
                return
            }
            if artworkURL != previousArtwork {
                group.coordinatorRoom.track.artworkURL = artworkURL
            }
        }
        .task {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }
                sonosService.monitor()
            let track = Track(trackID: "", name: "Dance The Night", artist: "Dua Lipa", album: "Barbie The Album", musicService: .apple, duration: 60, playbackPosition: .zero)
            track.artworkURL = await sonosService.getArtwork(from: track)
            print(track.artworkURL)
            group.coordinatorRoom.track = track
        }
    }
}

#Preview {
    NavigationStack {
        PlayerView(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "192.168.4.50", name: "Garage")]))
            .environment(SonosService())
            .environment(Popover())

    }
}

