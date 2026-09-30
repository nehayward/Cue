import MusicSearchKit
import SwiftUI

/// Asks whether there are Sonos speakers to set up. Cue is a player first, so
/// both answers lead somewhere complete: Yes goes on to the speaker search
/// (and the Local Network prompt it needs), No skips speakers entirely and
/// never touches the network. Either choice can be changed later in
/// Settings ▸ Sonos.
struct SonosQuestionStep: View {
    @State private var contentIn = false
    var answer: (_ hasSonos: Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Do you have Sonos?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Cue plays your music right here on this device. With Sonos speakers, it can play on them too.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 56)

            Spacer(minLength: 24)

            // The Sonos mark, the same asset the Sonos Radio service uses.
            // A black disc, so a faint ring and glow lift it off the
            // background.
            Image("Sonos Radio", bundle: .musicSearchKitBundle)
                .resizable()
                .scaledToFit()
                .frame(width: 168, height: 168)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1.5)
                }
                .shadow(color: .white.opacity(0.18), radius: 28)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 14)
                .scaleEffect(contentIn ? 1 : 0.8)
                .opacity(contentIn ? 1 : 0)
                .accessibilityLabel("Sonos")

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                PrimaryPillButton(title: "Yes, Set Up My Speakers") {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    answer(true)
                }

                Button {
                    HapticManager.shared.fireHaptic(.selection)
                    answer(false)
                } label: {
                    Text("No, Just This Device")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))

                Text("You can change this any time in Settings.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
            .opacity(contentIn ? 1 : 0)
            .offset(y: contentIn ? 0 : 24)
        }
        .task {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { contentIn = true }
        }
    }
}

#Preview {
    ZStack {
        MeshBackground().ignoresSafeArea()
        SonosQuestionStep { _ in }
    }
}
