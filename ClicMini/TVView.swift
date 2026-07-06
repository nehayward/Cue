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
            HStack(spacing: 8) {
                if let settings = device.TVSettings {
                    TVSettingsButton(
                        isActive: settings.nightMode,
                        label: settings.nightMode ? "On" : "Off",
                        systemImage: "moon.zzz.fill"
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
                        ArcUltraSpeechButton(
                            device: device,
                            speechLevel: speechLevel,
                            sonosService: sonosService
                        )
                    } else {
                        TVSettingsButton(
                            isActive: settings.dialogLevel,
                            label: settings.dialogLevel ? "On" : "Off",
                            systemImage: "person.wave.2.fill"
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            tvTileContent(systemImage: systemImage, label: label, isActive: isActive)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isActive)
    }
}

private struct ArcUltraSpeechButton: View {
    let device: SonosDevice
    let speechLevel: SpeechLevel
    let sonosService: SonosMiniService
    @State private var showPopover = false

    var body: some View {
        Button { showPopover = true } label: {
            tvTileContent(systemImage: "person.wave.2.fill", label: speechLevel.title, isActive: speechLevel.isActive)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: speechLevel)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SpeechLevel.allCases, id: \.self) { level in
                    Button {
                        showPopover = false
                        Task {
                            try? await sonosService.setArcUltraSpeechLevel(device.ip, level: level)
                            if let updated = try? await sonosService.getTVSettings(ip: device.ip, isArcUltra: true) {
                                sonosService.updateDevice(device, keyPath: \.TVSettings, value: updated)
                            }
                        }
                    } label: {
                        HStack {
                            Text(level.title)
                            Spacer()
                            if speechLevel == level {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 120)
        }
    }
}

private func tvTileContent(systemImage: String, label: String, isActive: Bool) -> some View {
    VStack(spacing: 4) {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 16))
            .foregroundColor(isActive ? .accentColor : .secondary)
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(isActive ? .accentColor : .secondary)
    }
    .frame(width: 44, height: 44)
    .background(isActive ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
    .cornerRadius(8)
}
