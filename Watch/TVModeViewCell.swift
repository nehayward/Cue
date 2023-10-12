import SwiftUI
import SonosKit

struct TVModeViewCell: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom

    var body: some View {
        Section {
            HStack(alignment: .top) {
                if let settings = group.tvSettings {
                    Text(settings.audioInputFormat.description)
                }
                Spacer()
                VStack {
                    if let settings = Binding<TVSettings>($group.tvSettings) {
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
        }
    }
}

#Preview {
    List {
        TVModeViewCell(group: .constant(.theater))
            .environment(SonosService())
    }
    .listStyle(.carousel)
}

