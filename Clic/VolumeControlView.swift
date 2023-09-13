import UIKit
import SwiftUI
import SonosKit

struct VolumeControlView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom
    @State private var isEditing: Bool = false
    @State private var volumeTask: Task<Void, Error>?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Image(systemName: "speaker.wave.3.fill", variableValue: group.groupVolume/100)
                .fixedSize()
                .padding(.trailing, 8)
            Slider(value: $group.groupVolume, in: 0...100, step: 2) { isEditing in
                self.isEditing = isEditing
                if !isEditing {
                    updateVolume(volume: group.groupVolume)
                }
            }
            .sensoryFeedback(.impact(flexibility: .solid), trigger: group.groupVolume) { oldValue, newValue in
                isEditing
            }
            Text("\(group.groupVolume, specifier: "%02.0f")%")
                .monospacedDigit()
                .animation(nil, value: group.groupVolume)
                .frame(width: 38, alignment: .trailing)
        }
        .font(.caption)
        .fontDesign(.rounded)
        .onChange(of: group.groupVolume) {
            if isEditing {
                updateVolume(volume: group.groupVolume)
            }
        }
        .animation(.snappy, value: group.groupVolume)
    }

    private func updateVolume(volume: Double) {
        volumeTask?.cancel()
        volumeTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            try Task.checkCancellation()
            group.groupVolume = volume
            await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(volume))
            if volume.isZero {
                try? await Task.sleep(for: .milliseconds(200))
                await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
            }
        }
    }
}

#Preview {
    return VolumeControlView(group: .constant(.garage))
        .environment(SonosService())
}
