import SwiftUI
import SonosKit

/// Shared Arc Ultra speech-enhancement menu used by TVModeViewCell, LargePlayerView, and MiniPlayerView.
struct SpeechEnhancementMenu: View {
    let group: GroupRoom
    /// When true, omits the large icon font and fixed frame (for compact / mini-player contexts).
    var compact: Bool = false
    /// When true, shows the current level title below the button (only when active).
    var showLabel: Bool = false

    private var speechLevel: SpeechLevel { group.tvSettings?.speechLevel ?? .off }

    var body: some View {
        Menu {
            ForEach(SpeechLevel.allCases, id: \.self) { level in
                Button {
                    Task {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        group.tvSettings?.speechEnhanceEnabled = level.isActive
                        if level.isActive { group.tvSettings?.dialogLevelValue = level.rawValue }
                        try? await SonosService.shared.setArcUltraSpeechLevel(group.coordinatorRoom.ip, level: level.rawValue)
                        if let updated = try? await SonosService.shared.getTVSettings(group: group) {
                            group.tvSettings = updated
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
            Image(systemName: "person.wave.2.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(speechLevel.isActive ? .accent : .secondary.opacity(0.8))
                .font(compact ? nil : .title)
                .frame(width: compact ? nil : 40, height: compact ? nil : 36)
        }
        .buttonStyle(.bordered)
        .tint(speechLevel.isActive ? .accent : nil)
        .animation(.spring, value: speechLevel)
        .disabled(group.tvSettings == nil)
        .accessibilityLabel("Speech Enhancement")
        .accessibilityValue(speechLevel.title)
        .overlay(alignment: .bottom) {
            if showLabel && speechLevel.isActive {
                Text(speechLevel.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .offset(y: 18)
            }
        }
    }
}
