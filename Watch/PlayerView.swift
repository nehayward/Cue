import NukeUI
import Collections
import SwiftUI
import MusicSearchKit
import SonosKitMini

struct PlayerView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(SonosMiniService.self) private var sonosService: SonosMiniService
    @Environment(Popover.self) var popOver: Popover
    
    let id: String
    
    @State private var isIdle: Bool = true
    @State private var showGroup: Bool = false
    @State private var volumeTask: Task<Void, Error>?
    
    var body: some View {
        if let deviceIndex = sonosService.devices.firstIndex(where: { $0.id == id }) {
            deviceView(for: deviceIndex)
        } else {
            Text("Vanished")
        }
    }
    
    @ViewBuilder
    func deviceView(for index: Int) -> some View {
        @Bindable var sonosService = sonosService
        let device = sonosService.devices[index]
        let deviceBinding = $sonosService.devices[index]
        
        VStack(spacing: 0) {
            ThumbnailView(id: id)
            Text(device.track.song)
                .bold()
                .lineLimit(1)
            Text(device.track.artist)
                .foregroundColor(.secondary)
                .lineLimit(1)
            HStack {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    Task {
                        await sonosService.previous(ip: device.ip)
                        try? await sonosService.updateTracks(for: [device])
                    }
                } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.liveActivity)
                Button(action: {
                    Task {
                        if device.isPlaying {
                            WKInterfaceDevice.current().play(.click)
                            await sonosService.pause(IP: device.ip)
                        } else {
                            WKInterfaceDevice.current().play(.click)
                            await sonosService.play(device.ip)
                        }
                    }
                }, label: {
                    Image(systemName: device.isPlaying ? "pause" : "play")
                        .resizable()
                        .scaledToFit()
                        .contentTransition(.symbolEffect(.automatic))
                        .frame(width: 28, height: 28, alignment: .center)
                        .symbolVariant(.fill)
                })
                .buttonStyle(.liveActivity)

                Button {
                    WKInterfaceDevice.current().play(.click)
                    Task {
                        await sonosService.next(ip: device.ip)
                        try? await Task.sleep(for: .milliseconds(100))
                        try? await sonosService.updateTracks(for: [device])
                    }
                } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.liveActivity)
            }
            .frame(maxHeight: 44)
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
                    Image(systemName: "hifispeaker.arrow.forward.fill")
                        .symbolRenderingMode(.monochrome)
                        .frame(width: 24)
                        .accessibilityLabel("Group Speakers")
                        .foregroundStyle(.white)
                        .tint(.white)
                }
            }
        }
        .sheet(isPresented: $showGroup) {
            GroupScreen(id: device.id)
        }
        .onChange(of: device.groupVolume) {
            if isIdle { return }
            volumeTask?.cancel()
            let volume = Int(device.groupVolume)
            volumeTask = Task {
                print("Changing")
                do {
                    try await Task.sleep(for: .milliseconds(100))
                    try? Task.checkCancellation()
                } catch {
                    print(error)
                    print("Cancelled??")
                }
                await sonosService.setGroupVolume(ip: device.ip, volume: volume)
            }
        }
        .navigationTitle(device.nameWithCount)
        .animation(.spring, value: popOver.isShowing)
        .focusable()
        .digitalCrownRotation(detent: deviceBinding.groupVolume,
                              from: 0,
                              through: 100,
                              by: 2,
                              sensitivity: .low,
                              isContinuous: false,
                              isHapticFeedbackEnabled: true,
                              onChange: { crownEvent in
            isIdle = false
            popOver.isShowing = !isIdle
            popOver.text = String(format: "%.0f", deviceBinding.groupVolume.wrappedValue)
        }, onIdle: {
            isIdle = true
            withAnimation(.spring.delay(0.5)) {
                popOver.isShowing = !isIdle
            }
        })
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active {
                Task {
                    try? await sonosService.updateWatchDevices(from: [device])
                }
            }
        }
        .animation(.interactiveSpring, value: device.groupVolume)
    }
}

//#Preview {
//    NavigationStack {
//        PlayerView(id: .constant("id"))
//            .environment(SonosMiniService())
//            .environment(Popover())
//
//    }
//}
