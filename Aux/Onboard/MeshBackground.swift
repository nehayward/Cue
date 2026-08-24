import SwiftUI

/// Full-screen black + teal mesh gradient backdrop used behind every onboarding
/// step. Internally calls `.ignoresSafeArea()` so it bleeds to the screen edges
/// even when placed inside a sheet that's safe-area-bounded.
struct MeshBackground: View {
    /// Deep, near-black teal anchoring the gradient.
    private let deepTeal = Color(red: 0.01, green: 0.07, blue: 0.10)
    /// Mid teal — bridges the black to the brand accent.
    private let midTeal = Color(red: 0.04, green: 0.28, blue: 0.34)
    /// Bright airy teal for the highlights.
    private let brightTeal = Color(red: 0.55, green: 0.88, blue: 0.92)

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if #available(iOS 18.0, macOS 15.0, visionOS 2.0, *) {
                StaticMeshGradient(
                    deepTeal: deepTeal,
                    midTeal: midTeal,
                    brightTeal: brightTeal
                )
            } else {
                LinearGradient(
                    colors: [deepTeal, midTeal, .accentColor, brightTeal.opacity(0.65)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blur(radius: 80)
            }

            // Vignette darkens edges for a more cinematic feel
            RadialGradient(
                colors: [.clear, .black.opacity(0.65)],
                center: .center,
                startRadius: 200,
                endRadius: 760
            )

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        // Pure decoration — VoiceOver shouldn't see the gradient, vignette,
        // or any of the rotating mesh stops as separate elements.
        .accessibilityHidden(true)
    }
}

@available(iOS 18.0, macOS 15.0, visionOS 2.0, *)
private struct StaticMeshGradient: View {
    let deepTeal: Color
    let midTeal: Color
    let brightTeal: Color

    var body: some View {
        // Static mesh — no TimelineView, no per-frame sin/cos, no per-frame
        // gradient re-blend. The previous animated version was barely
        // perceptible and was the single most expensive view on screen;
        // this renders once, sits there, and looks the same.
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                .black,
                deepTeal,
                .black,
                midTeal,
                Color.accentColor.opacity(0.9),
                midTeal,
                .black,
                deepTeal,
                brightTeal.opacity(0.55)
            ]
        )
    }
}
