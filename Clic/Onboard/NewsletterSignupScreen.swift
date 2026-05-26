import SwiftUI

/// Standalone newsletter sheet for users who skipped (or want to re-do) the
/// email step from onboarding. Reuses the same mesh background and `EmailStep`
/// view, with a top-trailing dismiss button. Used from `PreferenceScreen`.
struct NewsletterSignupScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            MeshBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("Stay in the Loop")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("New features and the occasional tip.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.top, 56)
                .padding(.bottom, 8)

                EmailStep(advance: { dismiss() }, source: "ios-preferences")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                Button {
                    HapticManager.shared.fireHaptic(.selection)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .padding(.top, 8)
                .padding(.trailing, 16)
            }
        }
        .fontDesign(.rounded)
        .preferredColorScheme(.dark)
    }
}
