import SwiftUI
import SonosKit

struct TVModeViewCell: View {
    @Environment(SonosService.self) var sonosService: SonosService
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
                            try? await sonosService.setNightMode(group.coordinatorRoom.ip, enabled: !settings.nightMode.wrappedValue)
                            group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                        }
                    } label: {
                        Label("Night Mode", systemImage: "moon.zzz.fill")
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .toggleStyle(.button)
                            .foregroundStyle(settings.nightMode.wrappedValue ? .accent : .secondary.opacity(0.8))
                    }
                    .buttonStyle(.bordered)
                    .tint(settings.nightMode.wrappedValue ? .accent : nil)
                    .animation(.spring, value: settings.nightMode.wrappedValue)

                    Button {
                        Task {
                            try? await sonosService.setDialogLevel(group.coordinatorRoom.ip, enabled:  !settings.dialogLevel.wrappedValue)
                            group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                        }
                    } label: {
                        Label("Dialog Mode", systemImage: "person.wave.2.fill")
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .toggleStyle(.button)
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
        }
    }
}

#Preview {
    List {
        TVModeViewCell(group: .constant(.theater))
            .environment(SonosService())
    }
}

