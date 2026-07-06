import SwiftUI
import SonosKitMini

struct TVView: View {
    @Environment(SonosMiniService.self) var sonosService
    var device: SonosDevice

    var body: some View {
        VStack {
            Link(destination: URL(string: "clic://device?id=\(device.id)")!) {
                Text(device.tvAudio)
                    .bold()
            }
            .foregroundStyle(.primary)
            HStack {
                if let settings = device.TVSettings {
                    TVSettingsButton(
                        isActive: settings.nightMode,
                        label: settings.nightMode ? "On" : "Off",
                        systemImage: "moon.zzz.fill",
                        accessibilityLabel: "Night Mode"
                    ) {
                        Task {
                            try? await sonosService.setNightMode(device.ip, enabled: !settings.nightMode)
                            if let updated = try? await sonosService.getTVSettings(ip: device.ip, isArcUltra: device.isArcUltra) {
                                sonosService.updateDevice(device, keyPath: \.TVSettings, value: updated)
                            }
                        }
                    }

                    if device.isArcUltra {
                        let speechLevel = settings.speechLevel
                        TVSettingsMenu(
                            isActive: speechLevel.isActive,
                            label: speechLevel.title,
                            systemImage: "person.wave.2.fill"
                        ) {
                            ForEach(SpeechLevel.allCases, id: \.self) { level in
                                Button {
                                    Task {
                                        try? await sonosService.setArcUltraSpeechLevel(device.ip, level: level)
                                        if let updated = try? await sonosService.getTVSettings(ip: device.ip, isArcUltra: true) {
                                            sonosService.updateDevice(device, keyPath: \.TVSettings, value: updated)
                                        }
                                    }
                                } label: {
                                    if speechLevel == level {
                                        Label(level.title, systemImage: "checkmark")
                                    } else {
                                        Text(level.title)
                                    }
                                }
                            }
                        }
                        .animation(.spring(response: 0.3), value: speechLevel)
                    } else {
                        TVSettingsButton(
                            isActive: settings.dialogLevel,
                            label: settings.dialogLevel ? "On" : "Off",
                            systemImage: "person.wave.2.fill",
                            accessibilityLabel: "Dialog Mode"
                        ) {
                            Task {
                                try? await sonosService.setDialogLevel(device.ip, enabled: !settings.dialogLevel)
                                if let updated = try? await sonosService.getTVSettings(ip: device.ip) {
                                    sonosService.updateDevice(device, keyPath: \.TVSettings, value: updated)
                                }
                            }
                        }
                    }
                }
            }
        }
        .fontDesign(.rounded)
        .frame(maxWidth: .infinity)
    }
}

private struct TVSettingsButton: View {
    let isActive: Bool
    let label: String
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            tvButtonContent(systemImage: systemImage, label: label, isActive: isActive)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isActive)
    }
}

private struct TVSettingsMenu<Items: View>: View {
    let isActive: Bool
    let label: String
    let systemImage: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu(content: items) {
            tvButtonContent(systemImage: systemImage, label: label, isActive: isActive)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

private func tvButtonContent(systemImage: String, label: String, isActive: Bool) -> some View {
    ZStack(alignment: .bottom) {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .foregroundColor(isActive ? .accentColor : .secondary)
            .padding(8)
            .padding(.bottom, 10)
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(isActive ? .accentColor : .secondary)
            .padding(.bottom, 4)
    }
    .background(isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
    .cornerRadius(6)
}
