import UIKit
import VibesDS
import SwiftUI
import SonosKitMini

struct GroupVolumeControlScreen: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(SonosMiniService.self) private var sonosService: SonosMiniService
    @Environment(Popover.self) var popOver: Popover
    
    let id: String

    var body: some View {
        Group {
            if let deviceIndex = sonosService.devices.firstIndex(where: { $0.id == id }) {
                deviceView(for: deviceIndex)
            } else {
                Text("Vanished")
            }
        }
        .onChange(of: scenePhase, initial: true) {
            if scenePhase == .active {
                print("Updated \(self)")
                updateScreen()
            }
        }
    }
    
    @ViewBuilder
    func deviceView(for index: Int) -> some View {
        let device = sonosService.devices[index]
        List {
            groupVolumeControl(for: device.id)
            if !device.rooms.isEmpty {
                ForEach(device.allDevices) { room in
                    volumeControl(for: room.id)
                }
            }
        }
    }
    
    @ViewBuilder
    func groupVolumeControl(for id: String) -> some View {
        @Bindable var sonosService = sonosService
        if let index = sonosService.devices.firstIndex(where: { $0.id == id }) {
            let device = sonosService.devices[index]
            let deviceBinding = $sonosService.devices[index]
            
            VStack(spacing: 0) {
                Text(device.nameWithCount)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            .frame(width: 28, height: 28)
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
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.liveActivity)
                    .buttonRepeatBehavior(.enabled)
                }
            }
            .animation(.spring, value: device.groupVolume)
        }
    }
    
    @ViewBuilder
    func volumeControl(for id: String) -> some View {
        @Bindable var sonosService = sonosService
        if let index = sonosService.devices.firstIndex(where: { $0.id == id }) {
            let device = sonosService.devices[index]
            let deviceBinding = $sonosService.devices[index]

            VStack(spacing: 0) {
                Text(device.name)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 0) {
                    Button {
                        Task {
                            await sonosService.setRelativeVolume(ip: device.ip, volume: -2)
                            deviceBinding.volume.wrappedValue = max(0, device.volume - 2)
                            await sonosService.updateGroupVolume(incomingDevices: [device])
                        }
                    } label: {
                        Image(systemName: "minus")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.liveActivity)
                    Text(device.volume, format: .number)
                        .font(.title2)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .strikethrough(device.isMuted ?? false, pattern: .solid, color: .red)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                        .opacity((device.isMuted ?? false) ? 0.4 : 1)
                    Button {
                        Task {
                            await sonosService.setRelativeVolume(ip: device.ip, volume: 2)
                            deviceBinding.volume.wrappedValue = min(100, device.volume + 2)
                            await sonosService.updateGroupVolume(incomingDevices: [device])
                        }
                    } label: {
                        Image(systemName: "plus")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.liveActivity)
                    .buttonRepeatBehavior(.enabled)
                }
            }
            .animation(.spring, value: device.volume)
        }
    }
    
    func updateScreen() {
        Task {
            guard let deviceIndex = sonosService.devices.firstIndex(where: { $0.id == id }) else {
                return
            }
            let device = sonosService.devices[deviceIndex]
            
            await withDiscardingTaskGroup { task in
                task.addTask {
                    await sonosService.updateRoomVolumes(incomingDevices: device.allDevices)
                }
                task.addTask {
                    await sonosService.updateRoomMuteState(incomingDevices: device.allDevices)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        GroupVolumeControlScreen(id: "RINCON_38420B780CEA01400")
            .environment(SonosMiniService.shared)
            .environment(Popover.shared)
            .task {
                try? await SonosMiniService.shared.loadWatch(useCache: false)
                await SonosMiniService.shared.updateRoomVolumes()
                await SonosMiniService.shared.updateRoomMuteState()
            }
    }
}

