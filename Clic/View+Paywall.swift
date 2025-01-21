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
                        Text("\(Image(systemName: "lock.fill")) Upgrade to Unlock")
                            .font(.body.smallCaps())
                            .bold()
                            .fontDesign(.rounded)
                            .foregroundStyle(.background.quaternary)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)
                }
        } else {
            self
        }
    }
}
