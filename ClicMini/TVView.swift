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
                    Button {
                        Task {
                            try? await sonosService.setNightMode(device.ip, enabled: !settings.nightMode)
                        }
                    } label: {
                        Label("Night Mode \(settings.nightMode ? "On": "Off")", systemImage: "moon.zzz.fill")
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .foregroundColor(settings.nightMode ? .accentColor : .secondary)
                            .padding(8)
                            .background(settings.nightMode ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.3), value: settings.nightMode)

                    if device.isArcUltra {
                        let speechLevel = settings.speechLevel
                        Menu {
                            ForEach(SpeechLevel.allCases, id: \.self) { level in
                                Button {
                                    Task {
                                        try? await sonosService.setArcUltraSpeechLevel(device.ip, level: level)
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
                            Label("Speech Enhancement \(speechLevel.title)", systemImage: "person.wave.2.fill")
                                .symbolRenderingMode(.hierarchical)
                                .labelStyle(.iconOnly)
                                .foregroundColor(speechLevel.isActive ? .accentColor : .secondary)
                                .padding(8)
                                .background(speechLevel.isActive ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .animation(.spring(response: 0.3), value: speechLevel)
                    } else {
                        Button {
                            Task {
                                try? await sonosService.setDialogLevel(device.ip, enabled: !settings.dialogLevel)
                            }
                        } label: {
                            Label("Dialog Mode \(settings.dialogLevel ? "On": "Off")", systemImage: "person.wave.2.fill")
                                .symbolRenderingMode(.hierarchical)
                                .labelStyle(.iconOnly)
                                .foregroundColor(settings.dialogLevel ? .accentColor : .secondary)
                                .padding(8)
                                .background(settings.dialogLevel ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.3), value: settings.dialogLevel)
                    }
                }
            }
        }
        .fontDesign(.rounded)
        .frame(maxWidth: .infinity)
    }
}
