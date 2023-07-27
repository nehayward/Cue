import UIKit
import SwiftUI
import SonosKit

struct GroupVolumeControlView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Bindable var group: GroupRoom

    @State var isEditingGroupVolume = false
    @State var isEditingRoomVolume = false
    @State var subviewHeight : CGFloat = 0

    @Binding var isExpanded: Bool


    init(group: GroupRoom, isExpanded: Binding<Bool>) {
        self.group = group
        self._isExpanded = isExpanded
    }

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "speaker.wave.3.fill", variableValue: group.groupVolume/100)
                Slider(value: $group.groupVolume, in: 0...100, step: 2) { isEditing in
                    self.isEditingGroupVolume = isEditing
                }
                .sensoryFeedback(.impact(flexibility: .solid), trigger: group.groupVolume, condition: { oldValue, newValue in
                    return !isEditingGroupVolume
                })
                .animation(.snappy, value: group.groupVolume)
                .onChange(of: group.groupVolume) {
                    if isEditingGroupVolume {
                        Task {
                            await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(group.groupVolume))
                        }
                    }
                }

                Text("\(group.groupVolume, specifier: "%03.0f")%")
                    .monospacedDigit()
                if group.rooms.count > 1 {
                    Button {
                        withAnimation(.bouncy(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "hifispeaker.2.fill")
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "speaker.wave.2.circle.fill")
                                    .resizable()
                                    .frame(width: 10, height: 10)
                                    .padding([.top, .trailing], -3)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 20)
            .padding(.bottom)

            VStack {
                ForEach($group.rooms) { $room in
                    VStack(alignment: .leading) {
                        Text(room.name)
                            .fontDesign(.rounded)
                            .font(.caption)
                        HStack {
                            Slider(value: $room.volume, in: 0...100, step: 2) { isEditing in
                                self.isEditingRoomVolume = isEditing
                            }
                            .sensoryFeedback(.impact(flexibility: .solid), trigger: room.volume)
                            Text("\(room.volume, specifier: "%03.0f")%")
                                .monospacedDigit()
                        }
                    }
                    .onChange(of: room.volume, initial: false) {
                        if isEditingRoomVolume {
                            Task {
                                await sonosService.setDeviceVolume(ip: room.ip, volume: Int(room.volume))
                                await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
                            }
                        }
                    }
                    .animation(.snappy, value: room.volume)
                    .sensoryFeedback(.impact(flexibility: .solid), trigger: room.volume)
                }
                Button {
                    for room in group.rooms {
                        Task {
                            await sonosService.setDeviceVolume(ip: room.ip, volume: Int(group.groupVolume))
                        }
                    }
                    Task {
                        try await Task.sleep(for: .seconds(1))
                        await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
//                        await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(group.groupVolume))
                    }
                } label: {
                   Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonBorderShape(.capsule)
                .buttonStyle(.borderedProminent)
            }
            .opacity(isExpanded ? 1 : 0)
            .scaleEffect(x: isExpanded ? 1 : 0.9)
        }
        .background(GeometryReader {
            Color.clear.preference(key: ViewHeightKey.self,
                                   value: $0.frame(in: .local).size.height)
        })
        .onPreferenceChange(ViewHeightKey.self) { subviewHeight = $0 }
        .frame(height: isExpanded ? subviewHeight : 30, alignment: .top)
        .padding()
        .clipped()
        .frame(maxWidth: .infinity)
    }

    struct ViewHeightKey: PreferenceKey {
        static var defaultValue: CGFloat { 0 }
        static func reduce(value: inout Value, nextValue: () -> Value) {
            value = value + nextValue()
        }
    }
}

#Preview {
    GroupVolumeControlView(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "", name: "Kitchen")]), isExpanded: .constant(true))
        .environment(SonosService())

}

