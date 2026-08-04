import AppKit

@MainActor
enum PanelBackground {
    /// Wraps `content` in a rounded, translucent background and returns the view to
    /// install as a window's `contentView`.
    ///
    /// On macOS 26 that's Liquid Glass, which matches the system's own floating
    /// panels and clips its own backdrop to `cornerRadius`. Earlier systems fall back
    /// to a corner-masked behind-window blur.
    ///
    /// `bordered` adds the hairline that keeps a panel edge readable against a light
    /// desktop. Glass draws its own edge, so it's ignored on macOS 26.
    static func wrap(_ content: NSView, frame: NSRect, cornerRadius: CGFloat, bordered: Bool = false) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }

        let effect = PanelEffectView(frame: frame, cornerRadius: cornerRadius, bordered: bordered)
        // Only size the content ourselves when it isn't driving its own layout —
        // autoresizing is ignored for a view using constraints, and stomping its
        // frame would fight them.
        if content.translatesAutoresizingMaskIntoConstraints {
            content.frame = effect.bounds
            content.autoresizingMask = [.width, .height]
        }
        effect.addSubview(content)
        return effect
    }

    /// Whether the wrapped background supplies its own separation from the desktop.
    /// Glass does, and stacking a window shadow on top of it reads heavy.
    static var drawsOwnShadow: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

/// Pre-macOS 26 panel background: a rounded behind-window blur, optionally with a
/// hairline border that stays visible in both appearances. A white border vanishes
/// against a light material, which is what left the panel edge looking undefined in
/// light mode.
final class PanelEffectView: NSVisualEffectView {
    private let bordered: Bool

    init(frame: NSRect, cornerRadius: CGFloat, bordered: Bool) {
        self.bordered = bordered
        super.init(frame: frame)
        blendingMode = .behindWindow
        state = .active
        material = .hudWindow
        applyRoundedCornerMask(radius: cornerRadius)
        if bordered {
            layer?.borderWidth = 1
            updateBorderColor()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorderColor()
    }

    private func updateBorderColor() {
        guard bordered else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let border = isDark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.10)
        layer?.borderColor = border.cgColor
    }
}

extension NSVisualEffectView {
    /// Rounds the corners of a `.behindWindow` effect view — backdrop included.
    ///
    /// `layer.cornerRadius` alone only clips what the *layer* draws. A behind-window
    /// blur is composited by the window server against the view's rectangular bounds,
    /// so the blurred backdrop keeps square corners. Over a dark desktop the leftover
    /// corners read as shadow and go unnoticed; over a light one they show up as bright
    /// square edges poking out from behind the rounded card. A mask image is what
    /// actually clips the backdrop.
    func applyRoundedCornerMask(radius: CGFloat) {
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.masksToBounds = true
        maskImage = .roundedCornerMask(radius: radius)
    }
}

extension NSImage {
    /// A rounded-rect stencil with cap insets, so `NSVisualEffectView.maskImage`
    /// stretches it to any size while keeping the corner radius fixed.
    static func roundedCornerMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
