import SwiftUI
import VibesDS

/// Speaker icons either side of a `VibeSlider` over `DeviceVolume`, for the
/// local player's surfaces. Greys out when the volume isn't ours to move —
/// see `DeviceVolume.isAvailable`.
struct LocalVolumeSlider: View {
    @State private var volume = DeviceVolume.shared
    /// The value while a drag is in flight, so the slider tracks the finger
    /// instead of the system's stepped echo.
    @State private var dragging: Double?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            VibeSlider(
                value: Binding(
                    get: { dragging ?? volume.level },
                    set: { value in
                        dragging = value
                        volume.set(value)
                    }
                ),
                in: 0...1,
                step: 0.01,
                baseHeight: 8,
                delayDrag: false,
                valueAnimation: nil
            ) { editing in
                if !editing { dragging = nil }
            }
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!volume.isAvailable)
        .opacity(volume.isAvailable ? 1 : 0.4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((volume.level * 100).rounded())) percent")
    }
}
