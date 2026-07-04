import SwiftUI
import SonosKit

struct TVModeViewCell: View {
    @Environment(Router.self) var router: Router

    let group: GroupRoom

    var body: some View {
        let settings = group.tvSettings
        let nightMode = settings?.nightMode ?? false
        let speechLevel = settings?.speechLevel ?? 0

        VStack(spacing: 4) {
            Text(settings?.audioInputFormat.description ?? " ")
                .bold()
                .tint(.primary)
            HStack(alignment: .top) {
                Button {
                    guard let settings else { return }
                    Task {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        try? await SonosService.shared.setNightMode(group.coordinatorRoom.ip, enabled: !settings.nightMode)
                        if let updated = try? await SonosService.shared.getTVSettings(group: group) {
                            group.tvSettings = updated
                        }
                    }
                } label: {
                    Label("Night Mode", systemImage: "moon.zzz.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .labelStyle(.iconOnly)
                        .toggleStyle(.button)
                        .foregroundStyle(nightMode ? .accent : .secondary.opacity(0.8))
                        .frame(width: 40, height: 36)
                }
                .buttonStyle(.bordered)
                .tint(nightMode ? .accent : nil)
                .animation(.spring, value: nightMode)
                .disabled(settings == nil)

                MuteButton(group: group)

                if group.isArcUltra {
                    VStack(spacing: 4) {
                        Menu {
                            ForEach([0, 1, 2, 3, 4], id: \.self) { level in
                                Button {
                                    Task {
                                        HapticManager.shared.fireHaptic(.buttonPress)
                                        // Optimistic update so the label changes immediately
                                        group.tvSettings?.speechEnhanceEnabled = level > 0
                                        if level > 0 { group.tvSettings?.dialogLevelValue = level }
                                        try? await SonosService.shared.setArcUltraSpeechLevel(group.coordinatorRoom.ip, level: level)
                                        if let updated = try? await SonosService.shared.getTVSettings(group: group) {
                                            group.tvSettings = updated
                                        }
                                    }
                                } label: {
                                    let labels = ["Off", "Low", "Medium", "High", "Max"]
                                    if speechLevel == level {
                                        Label(labels[level], systemImage: "checkmark")
                                    } else {
                                        Text(labels[level])
                                    }
                                }
                            }
                        } label: {
                            Label("Speech Enhancement", systemImage: "person.wave.2.fill")
                                .font(.title)
                                .symbolRenderingMode(.hierarchical)
                                .labelStyle(.iconOnly)
                                .foregroundStyle(speechLevel > 0 ? .accent : .secondary.opacity(0.8))
                                .frame(width: 40, height: 36)
                        }
                        .buttonStyle(.bordered)
                        .tint(speechLevel > 0 ? .accent : nil)
                        .animation(.spring, value: speechLevel)
                        .disabled(settings == nil)
                    }
                } else {
                    let dialogLevel = settings?.dialogLevel ?? false
                    Button {
                        guard let settings else { return }
                        Task {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            try? await SonosService.shared.setDialogLevel(group.coordinatorRoom.ip, enabled: !settings.dialogLevel)
                            if let updated = try? await SonosService.shared.getTVSettings(group: group) {
                                group.tvSettings = updated
                            }
                        }
                    } label: {
                        Label("Dialog Mode", systemImage: "person.wave.2.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .toggleStyle(.button)
                            .foregroundStyle(dialogLevel ? .accent : .secondary.opacity(0.8))
                            .frame(width: 40, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(dialogLevel ? .accent : .secondary.opacity(0.8))
                    .tint(dialogLevel ? .accent : nil)
                    .animation(.spring, value: dialogLevel)
                    .disabled(settings == nil)
                }
            }
        }
        .fontDesign(.rounded)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            Button {
                router.presentedSheet = .groupScreen(group: group)
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
        TVModeViewCell(group: .theater)
            .environment(SonosService())
    }
}
