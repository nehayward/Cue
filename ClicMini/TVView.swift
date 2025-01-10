import SwiftUI
import SonosKitMini

struct TVView: View {
    @Environment(SonosMiniService.self) var sonosService
    
    @Binding var group: SonosGroup
    
    var body: some View {
        VStack {
            Text(group.tvSettings?.audioInputFormat.description ?? "")
                .bold()
            HStack {
                if let settings = group.tvSettings {
                    Button {
                        Task {
                            try? await sonosService.setNightMode(group.coordinatorRoom.ip, enabled: !settings.nightMode)
                            group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                        }
                    } label: {
                        Label("Night Mode", systemImage: "moon.zzz.fill")
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .foregroundStyle(settings.nightMode ? .accent : .secondary.opacity(0.8))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(settings.nightMode ? .accent : nil)
                    .animation(.spring, value: settings.nightMode)
                    
                    Button {
                        Task {
                            try? await sonosService.setDialogLevel(group.coordinatorRoom.ip, enabled:  !settings.dialogLevel)
                            group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                        }
                    } label: {
                        Label("Dialog Mode", systemImage: "person.wave.2.fill")
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .foregroundStyle(settings.dialogLevel ? .accent : .secondary.opacity(0.8))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(settings.dialogLevel ? .accent : nil)
                    .animation(.spring, value: settings.dialogLevel)
                }
            }
        }
        .fontDesign(.rounded)
        .frame(maxWidth: .infinity)
    }
}

