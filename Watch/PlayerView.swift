import NukeUI
import Collections
import SwiftUI
import MusicSearchKit
import SonosKitMini

struct PlayerView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(Popover.self) var popOver: Popover
    
    @Binding var device: SonosDevice
    
    @State private var isIdle: Bool = true
    @State private var showGroup: Bool = false
    @State private var volumeTask: Task<Void, Error>?
    @State private var selectionTrack: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            ThumbnailView(device: device)
            Text(device.track.song)
                .bold()
                .lineLimit(1)
            Text(device.track.artist)
                .foregroundColor(.secondary)
                .lineLimit(1)
            HStack {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    selectionTrack?.cancel()
                    selectionTrack = Task {
                        await SonosMiniService.shared.previous(ip: device.ip)
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else {
                            return
                        }
                        try? await SonosMiniService.shared.updateTracks(for: [device])
                    }
                } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.liveActivity)
                Button(action: {
                    Task {
                        if device.isPlaying {
                            WKInterfaceDevice.current().play(.click)
                            await SonosMiniService.shared.pause(IP: device.ip)
                        } else {
                            WKInterfaceDevice.current().play(.click)
                            await SonosMiniService.shared.play(device.ip)
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
                    selectionTrack?.cancel()
                    selectionTrack = Task {
                        await SonosMiniService.shared.next(ip: device.ip)
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else {
                            return
                        }
                        try? await SonosMiniService.shared.updateTracks(for: [device])
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
                await SonosMiniService.shared.setGroupVolume(ip: device.ip, volume: volume)
                if device.groupIsMuted {
                    await SonosMiniService.shared.setGroupMute(device: device, mute: false)
                }
            }
        }
        .navigationTitle(device.nameWithCount)
        .animation(.spring, value: popOver.isShowing)
        .focusable()
        .overlay {
            TVView(id: device.id)
                .background(.thickMaterial)
                .opacity(device.isTVMode ? 1 : 0)
        }
        .digitalCrownRotation(detent: $device.groupVolume,
                              from: 0,
                              through: 100,
                              by: 1,
                              sensitivity: .low,
                              isContinuous: false,
                              isHapticFeedbackEnabled: true,
                              onChange: { crownEvent in
            isIdle = false
            popOver.isShowing = !isIdle
            popOver.text = String(format: "%.0f", device.groupVolume)
        }, onIdle: {
            isIdle = true
            withAnimation(.spring.delay(0.5)) {
                popOver.isShowing = !isIdle
            }
        })
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active {
                Task {
                    try? await SonosMiniService.shared.updateWatchDevices(from: [device])
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
