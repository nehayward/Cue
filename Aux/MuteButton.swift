import SwiftUI
import SonosKit

struct MuteButton: View {    
    let group: GroupRoom
    
    var body: some View {
        Button {
            Task {
                HapticManager.shared.fireHaptic(.buttonPress)
                await SonosService.shared.setGroupMute(group: group, mute: !group.isMuted)
                withAnimation {
                    group.isMuted.toggle()
                }
            }
        } label: {
            Label("Mute", systemImage: group.isMuted ? "speaker.slash.fill" : "speaker.fill")
                .contentTransition(.symbolEffect)
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .labelStyle(.iconOnly)
                .toggleStyle(.button)
                .foregroundStyle(group.isMuted ? .accent : .secondary.opacity(0.8))
                .frame(width: 40, height: 36)
        }
        .buttonStyle(.bordered)
        .foregroundStyle(group.isMuted ? .accent : .secondary.opacity(0.8))
        .tint(group.isMuted ? .accent : nil)
        .animation(.spring, value: group.isMuted)
    }
}

#Preview {
    @Previewable @State var group: GroupRoom = .theater
    MuteButton(group: group)
        .environment(SonosService.shared)
}
