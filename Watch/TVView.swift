import SwiftUI
import SonosKitMini

struct TVView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(SonosMiniService.self) private var sonosService: SonosMiniService
    @Environment(Popover.self) var popOver: Popover
    
    let id: String

    @State private var volumeTask: Task<Void, Error>?
    @State private var isIdle: Bool = true
    @State private var showGroup: Bool = false

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

        VStack(alignment: .center) {
            VStack {
                Text(device.TVSettings?.audioInputFormat?.description ?? "--")
                    .bold()
                
                Spacer()
                HStack {
                    Button {
                        Task {
                            try? await sonosService.setNightMode(device.ip, enabled: !nightMode)
                            try? await sonosService.updateWatchDevices(from: [device])
                        }
                    } label: {
                        Label("Night Mode", systemImage: "moon.zzz.fill")
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                    }
                    .buttonBorderShape(.roundedRectangle)
                    .opacity(nightMode ? 1 : 0.5)
                    Button {
                        Task {
                            await sonosService.setGroupMute(device: device)
                            try? await sonosService.updateWatchDevices(from: [device])
                        }
                    } label: {
                        Label("Mute", systemImage: device.groupIsMuted ? "speaker.slash.fill" : "speaker.fill")
                            .contentTransition(.symbolEffect)
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                    }
                    .buttonBorderShape(.roundedRectangle)
                    .opacity(!device.groupIsMuted ? 0.5 : 1)
                    
                    Button {
                        Task {
                            try? await sonosService.setDialogLevel(device.ip, enabled:  !speachEnhancement)
                            try? await sonosService.updateWatchDevices(from: [device])
                        }
                    } label: {
                        Label("Dialog Mode", systemImage: "person.wave.2.fill")
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                    }
                    .buttonBorderShape(.roundedRectangle)
                    .opacity(speachEnhancement ? 1 : 0.5)
                }
                
                HStack(spacing: 0) {
                    Button {
                        Task {
                            await sonosService.setRelativeGroupVolume(ip: device.ip, volume: -2)
                            deviceBinding.groupVolume.wrappedValue = max(0, device.groupVolume - 2)
                        }
                    } label: {
                        Image(systemName: "minus")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.liveActivity)
                    Text(device.groupVolume, format: .number)
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .strikethrough(device.groupIsMuted, pattern: .dash, color: .red)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                    Button {
                        Task {
                            await sonosService.setRelativeVolume(ip: device.ip, volume: 2)
                            deviceBinding.groupVolume.wrappedValue = min(100, device.groupVolume + 2)
                        }
                    } label: {
                        Image(systemName: "plus")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.liveActivity)
                    .buttonRepeatBehavior(.enabled)
                }
            }
            .animation(.spring, value: device.volume)
            .fontDesign(.rounded)
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
        }
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active {
                Task {
                    try? await sonosService.updateWatchDevices(from: [device])
                }
            }
        }
        .navigationTitle(device.nameWithCount)
    }
    
    var nightMode: Bool {
        guard let deviceIndex = sonosService.devices.firstIndex(where: { $0.id == id }),
              let tvSettings = sonosService.devices[deviceIndex].TVSettings else {
            return false
        }
                    
        return tvSettings.nightMode
    }
    
    
    var speachEnhancement: Bool {
        guard let deviceIndex = sonosService.devices.firstIndex(where: { $0.id == id }),
              let tvSettings = sonosService.devices[deviceIndex].TVSettings else {
            return false
        }
                    
        return tvSettings.dialogLevel
    }
}

#Preview {
    NavigationStack {
        TVView(id: "RINCON_48A6B80D8FB401400")
            .environment(SonosMiniService.shared)
            .environment(Popover())
            .task {
                try? await SonosMiniService.shared.loadWatch(useCache: true)
            }
    }
    .listStyle(.carousel)
}

