import SwiftUI

extension View {
    @ViewBuilder
    func glass26() -> some View {
#if !os(visionOS)
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear.interactive(), in: .containerRelative)
        } else {
            self.background {
                RoundedRectangle(cornerRadius: 8)
                    .foregroundStyle(.ultraThinMaterial)
            }
        }
#else
        self.background {
            RoundedRectangle(cornerRadius: 8)
                .foregroundStyle(.ultraThinMaterial)
        }
#endif
    }
    
    @ViewBuilder
    func toolbarBackground<S>(with glass: Bool = false, in shape: S) -> some View where S: InsettableShape {
#if !os(visionOS)
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
#else
        self
            .padding(8)
            .background(.thickMaterial, in: shape)
#endif
    }
    
    @ViewBuilder
    func backgroundExtension26() -> some View {
        #if !os(visionOS)
        if #available(iOS 26.0, *) {
            self.backgroundExtensionEffect()
        } else {
            self
        }
        #else
        // visionOS: no-op
        self
        #endif
    }
    
    @ViewBuilder
    func glassButton() -> some View {
        #if !os(visionOS)
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
        #else
        // visionOS fallback
        self
            .buttonStyle(.plain)
            .padding(8)
            .background(.thickMaterial, in: .circle)
        #endif
    }
    
    @ViewBuilder
    func safeArea<V>(
        edge: VerticalEdge,
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> V
    ) -> some View where V: View {
        #if !os(visionOS)
        if #available(iOS 26.0, *) {
            self
                .safeAreaBar(edge: edge, content: content)
        } else {
            self
                .safeAreaInset(edge: edge, content: content)
        }
        #else
        // visionOS fallback
        self
            .safeAreaInset(edge: edge, content: content)
        #endif
    }
    
    @ViewBuilder
    func glassForegroundAudio() -> some View {
    #if !os(visionOS)
    if #available(iOS 26.0, *) {
        self.glassEffect(.clear, in: .capsule)
    } else {
        self.background {
            Capsule()
                .foregroundStyle(.ultraThinMaterial)
        }
    }
    #else
    // visionOS fallback (or no-op)
    self.background {
        Capsule()
            .foregroundStyle(.ultraThinMaterial)
    }
    #endif
    }

    @ViewBuilder
    func sectionIndex(_ label: String) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            self.sectionIndexLabel(label)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func scrollEdgeEffectHidden26(_ hidden: Bool = true) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            self.scrollEdgeEffectHidden(hidden, for: .top)
        } else {
            self
        }
    }
}
