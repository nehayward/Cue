import SwiftUI
import SonosKit

struct TVModeViewCell: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom

    var body: some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                    Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
                }
                .padding()
                if let settings = group.tvSettings {
                    Text(settings.audioInputFormat.description)
                        .padding(.leading)
                }
                Spacer()
                HStack {
                    if let settings = Binding<TVSettings>($group.tvSettings) {
                        Toggle("Night Mode", systemImage: "moon.zzz", isOn: settings.nightMode)
                            .symbolVariant(settings.nightMode.wrappedValue ? .fill : .none)
                            .labelStyle(.iconOnly)
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
                            .onChange(of: settings.dialogLevel.wrappedValue) { oldValue, newValue in
                                Task {
                                    try? await sonosService.setDialogLevel(group.coordinatorRoom.ip, enabled: newValue)
                                    group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                                }
                            }
                    }
                }
                .padding(.bottom)
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

