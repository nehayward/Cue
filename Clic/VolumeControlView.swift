import UIKit
import SwiftUI
import SonosKit
import VibesDS

struct VolumeControlView: View {
    @Environment(SonosService.self) private var sonosService: SonosService
    @Binding var group: GroupRoom
    @State private var isEditing: Bool = false
    @State private var volumeTask: Task<Void, Error>?
    private let touchDelay: TimeInterval

    init(group: Binding<GroupRoom>, touchDelay: TimeInterval = 0) {
        self._group = group
        self.touchDelay = touchDelay
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                Task {
                    await sonosService.setGroupMute(group: group, mute: !group.isMuted)
                }
            } label: {
                Image(systemName: group.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: group.groupVolume/100)
                    .renderingMode(.template)
                    .foregroundColor(.accentColor)
                    .padding(.trailing, 8)
            }
            .frame(width: 24, alignment: .leading)
            .buttonStyle(.plain)

            VibeSlider(value: $group.groupVolume, touchDelay: touchDelay) { isEditing in
                if group.isMuted {
                    Task {
                        await sonosService.setGroupMute(group: group, mute: false)
                    }
                }
                self.isEditing = isEditing
                updateVolume(volume: group.groupVolume)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(isEditing ? 0 : 2))
                    print(isEditing)
                    group.isEditingVolume = isEditing
                }
            }
            .foregroundStyle(.accent)
//            .sensoryFeedback(.selection, trigger: group.groupVolume) { _, _ in
//                isEditing
//            }
            Text("\(group.groupVolume, specifier: "%03.0f")%")
                .contentTransition(.numericText())
                .monospacedDigit()
                .animation(.spring.speed(2), value: group.groupVolume)
                .frame(width: 38, alignment: .trailing)
                .fontDesign(.rounded)
        }
        .font(.caption)
        .fontDesign(.rounded)
        .animation(.interactiveSpring, value: group.groupVolume)
    }

    private func updateVolume(volume: Double) {
        volumeTask?.cancel()
        volumeTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            try Task.checkCancellation()
            await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(volume))
            if volume.isZero {
                try? await Task.sleep(for: .milliseconds(200))
                await sonosService.snapShotGroup(ip: group.coordinatorRoom.ip)
            }
        }
    }
}

#Preview {
    VolumeControlView(group: .constant(.garage))
        .environment(SonosService())
        .onAppear {
            let thumbImage = UIImage()
            UISlider.appearance().setThumbImage(thumbImage, for: .normal)
        }
}
