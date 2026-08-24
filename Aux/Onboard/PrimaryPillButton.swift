import SwiftUI

/// The CTA pill used across every onboarding step. Glass-effect capsule on
/// iOS/macOS 26+, falls back to an `.ultraThinMaterial` capsule on older OSes.
struct PrimaryPillButton: View {
    let title: String
    var icon: String? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.headline)
                }
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .padding(.horizontal, 22)
            .foregroundStyle(.white)
            .opacity(isDisabled ? 0.55 : 1)
            // Without this, only the text/icon glyph is the hit region — the
            // padding around them is transparent and ignores taps. `.contentShape`
            // tells SwiftUI the whole padded capsule is the tap target.
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            // Static teal aura — a `repeatForever` here added measurable CPU
            // overhead per pill across multiple mounted steps.
            Capsule()
                .fill(Color.accentColor.opacity(0.25))
                .blur(radius: 22)
        }
        .glassPill()
        // Cap pill width so it doesn't span the entire iPad / Mac window —
        // the existing horizontal padding handles iPhone widths. Centred
        // when the available width exceeds the cap.
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity)
        .disabled(isDisabled)
    }
}

extension View {
    /// Capsule glass treatment. Uses iOS 26 `.glassEffect` when available,
    /// falls back to a tinted `.ultraThinMaterial` capsule on older OSes.
    @ViewBuilder
    func glassPill() -> some View {
        #if !os(visionOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().fill(.white.opacity(0.10))
                }
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                }
        }
        #else
        self
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1)
            }
        #endif
    }
}
