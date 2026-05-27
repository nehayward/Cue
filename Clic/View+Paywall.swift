import SwiftUI

extension View {
    @ViewBuilder
    func paywall(_ isEnabled: Bool) -> some View {
        if !isEnabled {
            disabled(!isEnabled)
                .selectionDisabled(!isEnabled)
                .redacted(reason: .placeholder)
                .frame(maxWidth: .infinity)
                .overlay {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        Router.main.sheet(to: .paywall)
                    } label: {
                        ZStack {
                            // Transparent fill stretches the tap target to the
                            // whole row so users can tap anywhere on the redacted
                            // content to open the paywall.
                            Color.clear

                            HStack(spacing: 8) {
                                Image(systemName: "lock.fill")
                                    .font(.subheadline.weight(.semibold))
                                Text("Get Clic Super")
                                    .font(.subheadline.weight(.semibold))
                                    .fontDesign(.rounded)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.22))
                                    .blur(radius: 18)
                            )
                            .glassPill()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
        } else {
            self
        }
    }
}
