import SwiftUI

/// Renders the `CueIconGlass` asset (a render of the app icon, `Icon.icon`,
/// since an Icon Composer icon can't be drawn with `Image`) with
/// a soft drop shadow, a teal halo, and a slow ~3.4s vertical drift so it
/// feels like it's floating above the mesh background. The asset already
/// carries the rounded square + sheen + glyph baked in — no need to compose
/// the tile in SwiftUI anymore.
struct FloatingAppIcon: View {
    @State private var float = false

    var body: some View {
        Image("CueIconGlass")
            .resizable()
            .scaledToFit()
            // Flatten the icon + shadows into a single rasterised pass so
            // the shadow blur doesn't recompute every frame as the tile
            // moves via the float offset.
            .compositingGroup()
            .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 14)
            .shadow(color: Color.accentColor.opacity(0.30), radius: 28)
            .offset(y: float ? -6 : 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cue")
            .accessibilityAddTraits(.isImage)
            .onAppear {
                withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                    float = true
                }
            }
    }
}
