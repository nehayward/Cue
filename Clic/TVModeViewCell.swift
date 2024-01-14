import SwiftUI
import SonosKit

struct TVModeViewCell: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(RouterPath.self) var routePath: RouterPath
    @Binding var group: GroupRoom

    var body: some View {
        VStack {
            if let settings = Binding<TVSettings>($group.tvSettings) {
                Text(settings.wrappedValue.audioInputFormat.description)
                    .tint(.primary)
                HStack {
                    Toggle("Night Mode", systemImage: "moon.zzz", isOn: settings.nightMode)
                        .symbolVariant(settings.nightMode.wrappedValue ? .fill : .none)
                        .labelStyle(.iconOnly)
                        .contentShape(.circle)
                        .toggleStyle(.button)
                        .onChange(of: settings.nightMode.wrappedValue) { oldValue, newValue in
                            Task {
                                try? await sonosService.setNightMode(group.coordinatorRoom.ip, enabled: newValue)
                                group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                            }
                        }

                    Toggle("Dialog Mode", systemImage: "person.wave.2", isOn: settings.dialogLevel)
                        .symbolVariant(settings.dialogLevel.wrappedValue ? .fill : .none)
                        .labelStyle(.iconOnly)
                        .toggleStyle(.button)
                        .contentShape(.circle)
                        .onChange(of: settings.dialogLevel.wrappedValue) { oldValue, newValue in
                            Task {
                                try? await sonosService.setDialogLevel(group.coordinatorRoom.ip, enabled: newValue)
                                group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                            }
                        }
                }
            }
        }
        .fontDesign(.rounded)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            Button {
                routePath.presentedSheet = .groupScreen(groupScreenViewModel: GroupScreenViewModel(groupCoordinatorID: group.coordinatorID, sonosService: sonosService), group: group)
            } label: {
                Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" :  "hifispeaker.fill")
                    .frame(width: 20)
                    .foregroundStyle(.tint, .thickMaterial)
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

