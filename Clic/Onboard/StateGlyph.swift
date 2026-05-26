import SwiftUI

/// Static, oversized symbol for terminal discovery states (denied / notFound).
/// Sits inside a frosted-glass circle so it reads as a "status badge" rather
/// than a plain icon.
struct StateGlyph: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 72, weight: .light))
            .foregroundStyle(tint)
            .padding(36)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1)
                    }
            }
            // Parent header text already describes the state ("Can't reach
            // your network" / "No Sonos found"), so this glyph is decorative.
            .accessibilityHidden(true)
    }
}
