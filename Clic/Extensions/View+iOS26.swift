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
    
    @ViewBuilder
    func glassButton() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.plain)
                .padding(8)
                .glassEffect(.clear.interactive())
        } else {
            self
                .buttonStyle(.plain)
                .padding(8)
                .background(.thickMaterial, in: .circle)
        }
    }
    
    @ViewBuilder
    func safeArea<V>(edge: VerticalEdge, alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> V) -> some View where V : View {
        if #available(iOS 26.0, *) {
            self
                .safeAreaBar(edge: edge, content: content)
        } else {
            self
                .safeAreaInset(edge: edge, content: content)
        }
    }
    
    @ViewBuilder
    func glassForegroundAudio() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear, in: .capsule)
        } else {
            self.background {
                Capsule()
                    .foregroundStyle(.ultraThinMaterial)
            }
        }
    }
}
