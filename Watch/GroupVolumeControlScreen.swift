import UIKit
import SwiftUI
import SonosKit

struct GroupVolumeControlScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom

    @State var isEditingGroupVolume = false
    @State private var volumeTask: Task<Void, Error>?

    @State var groupVolume: Double = 0

    var body: some View {
        ScrollView {
            VStack{
                Text("Group")
                Stepper(
                    onIncrement: {
                        let volumeChange = min(Int(group.groupVolume + 2), 100)
                        group.groupVolume = Double(volumeChange)

                        volumeTask?.cancel()
                        volumeTask = Task { @MainActor in
                            print("Changing \(group.coordinatorRoom.name)")
                            await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: volumeChange)
                            try? await sonosService.updateGroupsRooms(from: [group])
                        }
                    },
                    onDecrement: {
                        let volumeChange = max(Int(group.groupVolume - 2), 0)
                        group.groupVolume = Double(volumeChange)
                        volumeTask?.cancel()
                        volumeTask = Task {
                            print("Changing \(group.coordinatorRoom.name)")
                            await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: volumeChange)
                        }
                    },
                    onEditingChanged: { changed in
                        print(changed)
                    },
                    label: {
                        Text(group.groupVolume, format: .number)
                        //                    .monospacedDigit()
                    })
            }
            //            .onChange(of: group.groupVolume, initial: true) {
            //                groupVolume = group.groupVolume
            //            }
            //            .onChange(of: groupVolume, initial: false) {
            //                volumeTask?.cancel()
            //                volumeTask = Task {
            //                    print("Changing \(group.coordinatorRoom.name)")
            //                    try await Task.sleep(for: .milliseconds(200))
            //                    await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(groupVolume))
            //                }
            //            }
            Divider()
                .padding(.bottom)

            //            HStack {
            //                Text("Group")
            //                    .fontDesign(.rounded)
            //                Spacer()
            //                Text("\(group.groupVolume, specifier: "%03.0f")%")
            //                    .monospacedDigit()
            //            }
            //            HStack {
            //                Slider(value: $groupVolume, in: 0...100, step: 2) { isEditing in
            //                    print("Edit")
            //                    self.isEditingGroupVolume = isEditing
            //                }
            //                .sensoryFeedback(.impact(flexibility: .solid), trigger: group.groupVolume, condition: { oldValue, newValue in
            //                    return !isEditingGroupVolume
            //                })
            //                .animation(.snappy, value: group.groupVolume)
            //                .onChange(of: group.groupVolume) {
            //                    print("HERE")
            //                    if isEditingGroupVolume {
            //                        Task {
            //                            await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(group.groupVolume))
            //                        }
            //                    }
            //                }
            //            }


            ForEach(group.rooms) { room in
                VStack{
                    Text(room.name)
                        .font(.caption)
                    Stepper(
                        onIncrement: {
                            let volumeChange = min(Int(room.volume + 2), 100)
                            room.volume = Double(volumeChange)

                            volumeTask?.cancel()
                            volumeTask = Task {
                                print("Changing \(room.name)")
                                await sonosService.setDeviceVolume(ip: room.ip, volume: volumeChange)
                                try await Task.sleep(for: .milliseconds(200))
                                await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
                                if let volume = try? await sonosService.getGroupVolume(ip: group.ip) {
                                    group.groupVolume = volume
                                }
                            }
                        },
                        onDecrement: {
                            let volumeChange = max(Int(room.volume - 2), 0)
                            room.volume = Double(volumeChange)
                            volumeTask?.cancel()
                            volumeTask = Task {
                                print("Changing \(room.name)")
                                await sonosService.setDeviceVolume(ip: room.ip, volume: volumeChange)
                                try await Task.sleep(for: .milliseconds(200))
                                await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
                                if let volume = try? await sonosService.getGroupVolume(ip: group.ip) {
                                    group.groupVolume = volume
                                }
                            }
                        },
                        onEditingChanged: { changed in
                            print(changed)
                        },
                        label: {
                            Text(room.volume, format: .number)
                            //                    .monospacedDigit()
                        })
                    .controlSize(.small)

                }
            }
            //                .onChange(of: group.rooms, initial: true) {
            //                     = room.volume
            //                }
            //                .onChange(of: roomVolumes.) {
            //                    volumeTask?.cancel()
            //                    volumeTask = Task {
            //                        print("Changing \(group.coordinatorRoom.name)")
            //                        try await Task.sleep(for: .milliseconds(200))
            //                        await sonosService.setDeviceVolume(ip: room.ip, volume: Int(room.volume))
            //                    }
            //                }
            //                VStack {
            //                    //                            HStack {
            //                    //                                Text(room.name)
            //                    //                                    .fontDesign(.rounded)
            //                    //                                    .font(.caption)
            //                    //                            }
            //                    //
            //                    VStack(spacing: 0) {
            //                        Stepper(onIncrement: {
            //
            //                        }, onDecrement: {
            //
            //                        }, label: {
            //
            //                            Text("\(room.volume, specifier: "%0.0f")")
            //                                .monospacedDigit()
            //
            //                        })
            //                        Text(room.name)
            //                    }
            //
            //                    Stepper(value: $room.volume, step: 2, format: .number) {
            //                        Text("Garage")
            //                    } onEditingChanged: { testing in
            //                        print(testing)
            //                    }
            //                    .controlSize(.small)
            //
            //
            //
            //
            //
            //                    //                            Slider(value: $room.volume, in: 0...100, step: 2) { isEditing in
            //                    //
            //                    //                            }.onChange(of: room.volume) {
            //                    //                                volumeTask?.cancel()
            //                    //                                volumeTask = Task {
            //                    //                                    print("Changing \(room.name)")
            //                    //                                    try await Task.sleep(for: .milliseconds(200))
            //                    //                                    await sonosService.setDeviceVolume(ip: room.ip, volume: Int(room.volume))
            //                    //                                }
            //                    //                            }
            //                }
            //                .sensoryFeedback(.impact(flexibility: .solid), trigger: room.volume)

            Button {
                for room in group.rooms {
                    Task {
                        room.volume = group.groupVolume
                        await sonosService.setDeviceVolume(ip: room.ip, volume: Int(group.groupVolume))
                    }
                }
                Task {
                    try await Task.sleep(for: .seconds(1))
                    await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
                }
            } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    .bold()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle)
            .padding(.top, 20)

        }
        //        .navigationTitle("Volume Control")
        .padding([.leading, .trailing])
        //        .toolbar(.hidden, for: .navigationBar)
        //        .toolbarTitleDisplayMode(.inline)
        .containerBackground(.accent.gradient, for: .navigation)
    }
}

#Preview {
    NavigationStack {
        GroupVolumeControlScreen(group: .constant(.garage))
            .environment(SonosService())
    }
}

