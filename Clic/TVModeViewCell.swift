import SwiftUI
import SonosKit

struct TVModeViewCell: View {
    @Environment(Router.self) var routePath: Router
    @Binding var group: GroupRoom

    var body: some View {
        VStack {
            if let settings = Binding<TVSettings>($group.tvSettings) {
                Text(settings.wrappedValue.audioInputFormat.description)
                    .bold()
                    .tint(.primary)
                HStack {
                    Button {
                        Task {
                            try? await SonosService.shared.setNightMode(group.coordinatorRoom.ip, enabled: !settings.nightMode.wrappedValue)
                            group.tvSettings = try await SonosService.shared.getTVSettings(ip: group.coordinatorRoom.ip)
                        }
                    } label: {
                        Label("Night Mode", systemImage: "moon.zzz.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .toggleStyle(.button)
                            .foregroundStyle(settings.nightMode.wrappedValue ? .accent : .secondary.opacity(0.8))
                            .frame(width: 40, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(settings.nightMode.wrappedValue ? .accent : nil)
                    .animation(.spring, value: settings.nightMode.wrappedValue)
                    
                    MuteButton(group: group)

                    Button {
                        Task {
                            try? await SonosService.shared.setDialogLevel(group.coordinatorRoom.ip, enabled:  !settings.dialogLevel.wrappedValue)
                            group.tvSettings = try await SonosService.shared.getTVSettings(ip: group.coordinatorRoom.ip)
                        }
                    } label: {
                        Label("Dialog Mode", systemImage: "person.wave.2.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .toggleStyle(.button)
                            .foregroundStyle(settings.dialogLevel.wrappedValue ? .accent : .secondary.opacity(0.8))
                            .frame(width: 40, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(settings.dialogLevel.wrappedValue ? .accent : .secondary.opacity(0.8))
                    .tint(settings.dialogLevel.wrappedValue ? .accent : nil)
                    .animation(.spring, value: settings.dialogLevel.wrappedValue)
                }
            }
        }
        .fontDesign(.rounded)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            Button {
                routePath.presentedSheet = .groupScreen(group: group)
            } label: {
                Image(systemName: "tv.and.hifispeaker.fill")
                    .symbolRenderingMode(.hierarchical)
                    .fontDesign(.rounded)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .tint(.primary)
        }
    }
}

#Preview {
    List {
        TVModeViewCell(group: .constant(.theater))
            .environment(SonosService())
    }
}

