import MusicSearchKit
import SonosKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Onboarding's last page: what's set up, where it plays, and the way in.
/// The services chosen pop in as their marks, so the end of setup shows
/// what it did rather than the sheet just closing.
struct ReadyStep: View {
    let services: [MediaSearchService]
    var finish: () -> Void

    @Environment(SonosService.self) private var sonosService
    @State private var iconIn = false
    @State private var textIn = false
    @State private var marksIn = false
    @State private var ctaIn = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            FloatingAppIcon()
                .frame(width: 128, height: 128)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black, Color.accentColor)
                        .background(Circle().fill(.black).padding(4))
                        .offset(x: 10, y: 10)
                        .scaleEffect(iconIn ? 1 : 0.2)
                        .opacity(iconIn ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .scaleEffect(iconIn ? 1 : 0.7)
                .opacity(iconIn ? 1 : 0)

            VStack(spacing: 10) {
                Text("You’re all set")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 32)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 36)
            .opacity(textIn ? 1 : 0)
            .offset(y: textIn ? 0 : 14)

            if !services.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(services.enumerated()), id: \.element) { index, service in
                        ServiceMarkTile(service: service, size: 48)
                            .scaleEffect(marksIn ? 1 : 0.4)
                            .opacity(marksIn ? 1 : 0)
                            .animation(
                                .spring(response: 0.45, dampingFraction: 0.6).delay(Double(index) * 0.07),
                                value: marksIn
                            )
                    }
                }
                .environment(\.colorScheme, .dark)
                .padding(.top, 28)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(services.map(\.title).formatted(.list(type: .and)))
            }

            Spacer(minLength: 24)

            PrimaryPillButton(title: "Start Listening") {
                HapticManager.shared.fireHaptic(.notification(.success))
                finish()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
            .opacity(ctaIn ? 1 : 0)
            .offset(y: ctaIn ? 0 : 24)
        }
        .task {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) { iconIn = true }
            HapticManager.shared.fireHaptic(.notification(.success))
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeOut(duration: 0.4)) { textIn = true }
            try? await Task.sleep(for: .milliseconds(120))
            marksIn = true
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { ctaIn = true }
        }
    }

    /// Where Cue plays: this device, and the speakers found on the way.
    private var summary: String {
        let speakers = sonosService.isEnabled ? sonosService.rooms.count : 0
        let start = services.isEmpty
            ? "Add your music any time in Settings."
            : "Your music is ready to play on \(deviceName)"
        guard !services.isEmpty else { return start }
        switch speakers {
        case 0: return start + "."
        case 1: return start + ", and on your Sonos speaker."
        default: return start + ", and on your \(speakers) Sonos speakers."
        }
    }

    private var deviceName: String {
        #if targetEnvironment(macCatalyst)
        return "this Mac"
        #elseif canImport(UIKit) && !os(visionOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "this iPad" : "this iPhone"
        #else
        return "this device"
        #endif
    }
}

#Preview {
    ZStack {
        MeshBackground().ignoresSafeArea()
        ReadyStep(services: [.apple, .plex, .tuneIn]) { }
    }
    .withEnvironments()
}
