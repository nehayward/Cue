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
                        Menu {
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
                        } label: {
                            Label("Speech Enhancement", systemImage: "person.wave.2.fill")
                                .symbolRenderingMode(.hierarchical)
                                .labelStyle(.iconOnly)
                                .foregroundColor(speechLevel.isActive ? .accentColor : .secondary)
                                .padding(8)
                                .background(speechLevel.isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        }
                        .menuStyle(.button)
                        .buttonBorderShape(.roundedRectangle)
                        .contentShape(.rect)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .animation(.spring(response: 0.3), value: speechLevel)
                        .menuIndicator(.hidden)
                        .overlay(alignment: .bottom) {
                            Text(speechLevel.title)
                                .font(.caption.smallCaps())
                                .offset(y: 12)
                        }
                    } else {
                        TVSettingsButton(
                            isActive: settings.dialogLevel,
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
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(accessibilityLabel, systemImage: systemImage)
                .symbolRenderingMode(.hierarchical)
                .labelStyle(.iconOnly)
                .foregroundColor(isActive ? .accentColor : .secondary)
                .padding(8)
                .background(isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .cornerRadius(6)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isActive)
    }
}
