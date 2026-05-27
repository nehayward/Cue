import SonosKit
import SwiftUI

/// Live list of individual discovered speakers. Uses the same staggered
/// cascade as `ServicesStep` — rows fade-and-slide in one by one with a
/// short per-index delay, so the arrival reads as a deliberate reveal rather
/// than everything popping into place at once.
///
/// Note: in **Debug** builds the spring cascade can read as choppy because
/// SwiftUI's view diffing + animation runtime is dramatically slower without
/// the release optimizations. In Release / TestFlight builds this runs
/// smoothly. Don't tune the animation against debug-build framerates.
struct DiscoveredSpeakerList: View {
    let rooms: [Room]
    @State private var rowsIn = false

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                    SpeakerRow(room: room)
                        .opacity(rowsIn ? 1 : 0)
                        .offset(y: rowsIn ? 0 : 16)
                        .animation(
                            .spring(response: 0.55, dampingFraction: 0.85)
                                .delay(Double(index) * 0.06),
                            value: rowsIn
                        )
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        // Soft fade-in/out at the scroll edges — matches `ServicesStep` so
        // both lists feel like part of the same family.
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 12)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 24)
            }
        }
        .onAppear {
            rowsIn = true
            fireCascadeHaptics()
        }
    }

    /// Fires one haptic per row, with the same 60ms-per-index spacing as the
    /// row cascade — so each tap lands as its row springs in. The first row
    /// gets the heavier success notification ("we found it"), the rest get
    /// selection ticks.
    private func fireCascadeHaptics() {
        Task { @MainActor in
            for index in rooms.indices {
                if index > 0 { try? await Task.sleep(for: .milliseconds(60)) }
                if index == 0 {
                    HapticManager.shared.fireHaptic(.notification(.success))
                } else {
                    HapticManager.shared.fireHaptic(.selection)
                }
            }
        }
    }
}

private struct SpeakerRow: View {
    let room: Room

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: speakerSymbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(room.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(room.info?.modelDisplayName ?? "")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1, reservesSpace: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
        }
        // Flatten the row (fill + strokeBorder + content) into a single
        // composited group so the cascade's opacity/offset animation
        // doesn't re-blend the layered background every frame.
        .compositingGroup()
        // Combine the speaker icon + name + model into one VoiceOver element.
        // e.g. "Living Room, Sonos One"
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if let model = room.info?.modelDisplayName {
            return "\(room.name), \(model)"
        }
        return room.name
    }

    /// Pick an SF Symbol based on what the speaker actually is. Soundbars get
    /// the TV-style speaker glyph; everything else uses the stacked
    /// `hifispeaker` symbol.
    private var speakerSymbol: String {
        if room.isSoundbar { return "tv.and.hifispeaker.fill" }
        return "hifispeaker.fill"
    }
}
