import AppKit

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

/// The HUD panel background: a rounded behind-window blur with a hairline border
/// that stays visible in both appearances. A white border vanishes against a light
/// material, which is what left the panel edge looking undefined in light mode.
final class HUDEffectView: NSVisualEffectView {
    init(frame: NSRect, cornerRadius: CGFloat) {
        super.init(frame: frame)
        blendingMode = .behindWindow
        state = .active
        material = .hudWindow
        applyRoundedCornerMask(radius: cornerRadius)
        layer?.borderWidth = 1
        updateBorderColor()
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
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let border = isDark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.10)
        layer?.borderColor = border.cgColor
    }
}
