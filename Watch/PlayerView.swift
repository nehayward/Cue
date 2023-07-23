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
            AsyncImage(
                url: group.coordinatorRoom.track.artworkURL,
                transaction: Transaction(animation: .snappy)
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                default:
                    RoundedRectangle(cornerRadius: 12)
                        .foregroundStyle(.thinMaterial)
                }
            }
            .cornerRadius(12)
            .shadow(radius: 10)
            .frame(width: 80, height: 80)
            .focusable()
            .digitalCrownRotation(detent: $group.groupVolume,
                                  from: 0,
                                  through: 100,
                                  by: 1,
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
            Text(group.coordinatorRoom.track.artist)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background {
            AsyncImage(
                url: group.coordinatorRoom.track.artworkURL,
                transaction: Transaction(animation: .snappy)
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .blur(radius: 20)
                default:
                    RoundedRectangle(cornerRadius: 12)
                        .foregroundStyle(.thinMaterial)
                }
            }
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
                Button {
                    Task {
                        await sonosService.next(ip: group.coordinatorRoom.ip)
                    }
                } label: {
                    Image(systemName: "forward.end.fill")
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
        .navigationTitle(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
        .onAppear {
            volume = group.groupVolume
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

