import SwiftUI

extension View {
    @ViewBuilder
    func glass26() -> some View {
#if !os(visionOS)
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear.interactive(), in: .rect(cornerRadius: 12))
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
    func glass26(color: Color?) -> some View {
#if !os(visionOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular.tint(color?.opacity(0.5)), in: .rect(cornerRadius: 12))
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
        if #available(iOS 26.0, macOS 26.0, *) {
            if glass {
                self
                    .padding(8)
                    .glassEffect(.regular.interactive())
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
                .buttonStyle(.glass)
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

    /// Capsule toolbar treatment for a row of controls. Uses iOS 26 Liquid
    /// Glass when available, falls back to a `.thinMaterial` capsule on
    /// older OSes and visionOS.
    ///
    /// The row is wrapped in a `GlassEffectContainer` so any glass the
    /// controls inside contribute (a `Menu`'s source view, a glass button)
    /// composites with the capsule as one shared sample, instead of stacking
    /// into a darker, more opaque pill.
    @ViewBuilder
    func glassToolbar() -> some View {
        #if !os(visionOS)
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                self.glassEffect(.clear, in: .capsule)
            }
        } else {
            self.background(.thinMaterial, in: Capsule())
        }
        #else
        self.background(.thinMaterial, in: Capsule())
        #endif
    }

    /// Circular material backing for bottom-bar toolbar icons on OSes without
    /// Liquid Glass. iOS 26 and visionOS already render toolbar items in
    /// glass, so this only draws on older OSes.
    @ViewBuilder
    func glassToolbarIcon() -> some View {
        #if !os(visionOS)
        if #available(iOS 26.0, *) {
            self
        } else {
            self
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
        #else
        self
        #endif
    }

    /// A circular glass button that fills with the accent tint when `active`.
    /// Keeps the clear-glass look when inactive; on iOS 26 the active state is
    /// prominent (tinted) glass, older OSes fall back to an accent-filled
    /// material circle.
    @ViewBuilder
    func accentGlassButton(active: Bool) -> some View {
        #if !os(visionOS)
        if #available(iOS 26.0, *) {
            if active {
                self.buttonStyle(.glassProminent).tint(Color.accentColor)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self
                .buttonStyle(.plain)
                .padding(8)
                .background(active ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.thickMaterial), in: .circle)
        }
        #else
        self
            .buttonStyle(.plain)
            .padding(8)
            .background(active ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.thickMaterial), in: .circle)
        #endif
    }
    
    
    @ViewBuilder
    func safeArea<V>(
        edge: VerticalEdge,
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> V
    ) -> some View where V: View {
        self.safeAreaInset(edge: edge, content: content)
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
        if #available(iOS 26.0, macCatalyst 26.0, visionOS 26.0, *) {
            self.sectionIndexLabel(label)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func scrollEdgeEffectHidden26(_ hidden: Bool = true) -> some View {
        #if !os(visionOS)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            self.scrollEdgeEffectHidden(hidden, for: .top)
        } else {
            self
        }
        #else
        self
        #endif
    }
        
    @ViewBuilder
    func capsuleGlass() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            background(.ultraThinMaterial, in: .capsule)
        }
    }
}
