import UIKit
import SwiftUI
import SonosKit

struct GroupVolumeControlView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom

    @State var isEditingGroupVolume = false
    @State var isEditingRoomVolume = false
    @State var subviewHeight : CGFloat = 0

    @Binding var isExpanded: Bool
    @State private var volumeTask: Task<Void, Error>?

    var body: some View {
        VStack {
            HStack {
                VolumeControlView(group: $group)
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
                        HStack(spacing: 0) {
                            Image(systemName: "speaker.wave.3.fill", variableValue: group.groupVolume/100)
                                .fixedSize()
                                .padding(.trailing, 8)
                            Slider(value: $room.volume, in: 0...100, step: 2) { isEditing in
                                self.isEditingRoomVolume = isEditing
                                room.isEditingVolume = isEditing
                                let endingVolume = room.volume
                                if !isEditing {
                                    print(room.volume)
                                    print("Cancelled")
                                    volumeTask?.cancel()
                                    volumeTask = Task {
                                        try? await Task.sleep(for: .milliseconds(100))
                                        try Task.checkCancellation()
                                        print("Runnning")
                                        print(room.name)
                                        print(room.volume)
                                        print("Ending", endingVolume)
                                        await sonosService.setDeviceVolume(ip: room.ip, volume: Int(endingVolume))
                                        try await Task.sleep(for: .milliseconds(300))
                                        await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
                                    }
                                }
                            }
                            .sensoryFeedback(.impact(flexibility: .solid), trigger: room.volume) { _, _ in
                                isEditingRoomVolume
                            }
                            Text("\(room.volume, specifier: "%03.0f")%")
                                .monospacedDigit()
                        }
                    }
                    .onChange(of: room.volume, initial: false) {
                        if isEditingRoomVolume {
                            let endingVolume = room.volume
                            volumeTask?.cancel()
                            volumeTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                try Task.checkCancellation()
                                print(room.name)
                                await sonosService.setDeviceVolume(ip: room.ip, volume: Int(endingVolume))
                                try await Task.sleep(for: .milliseconds(300))
                                await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
                            }
                        }
                    }
                    .animation(.interactiveSpring, value: room.volume)
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
                    }
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        .bold()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
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
    GroupVolumeControlView(group: .constant(.garage), isExpanded: .constant(true))
        .environment(SonosService())

}

