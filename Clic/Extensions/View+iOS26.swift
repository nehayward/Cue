import SwiftUI

extension View {
    @ViewBuilder
    func glass26() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear.interactive(), in: .containerRelative)
        } else {
            self.background {
                RoundedRectangle(cornerRadius: 8)
                    .foregroundStyle(.ultraThinMaterial)
            }
        }
    }
    
    @ViewBuilder
    func toolbarBackground<S>(with glass: Bool = false, in shape: S) -> some View where S: InsettableShape {
        if #available(iOS 26.0, *) {
            if glass {
                self
                    .padding(8)
                    .glassEffect(.clear.interactive())
            } else {
                self
            }
        } else {
            self
                .padding(8)
                .background(.thickMaterial, in: shape)
        }
    }
    
    @ViewBuilder
    func backgroundExtension26() -> some View {
        if #available(iOS 26.0, *) {
            self.backgroundExtensionEffect()
        } else {
            self
        }
    }
}
