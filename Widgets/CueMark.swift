import SwiftUI

/// Cue's mark, the app icon's rounded play triangle: `Polygon 1.svg` in
/// `Cue/Icon.icon`, a path the icon draws with a 59-point stroke round it, in
/// its 654 × 725 view box. The widgets' corner glyph (`CueGlyph`) and Cue
/// Mini's menu bar icon both draw it.
struct CueMark: Shape {
    static let aspectRatio: CGFloat = 654 / 725

    private static let mark: Path = {
        var outline = Path()
        outline.move(to: CGPoint(x: 589, y: 301.432))
        outline.addCurve(to: CGPoint(x: 589, y: 422.676), control1: CGPoint(x: 635.667, y: 328.375), control2: CGPoint(x: 635.667, y: 395.733))
        outline.addLine(to: CGPoint(x: 134.5, y: 685.082))
        outline.addCurve(to: CGPoint(x: 29.5, y: 624.46), control1: CGPoint(x: 87.8333, y: 712.025), control2: CGPoint(x: 29.5, y: 678.346))
        outline.addLine(to: CGPoint(x: 29.5, y: 99.6484))
        outline.addCurve(to: CGPoint(x: 134.5, y: 39.0267), control1: CGPoint(x: 29.5, y: 45.7624), control2: CGPoint(x: 87.8333, y: 12.0837))
        outline.closeSubpath()
        return outline.union(outline.strokedPath(StrokeStyle(lineWidth: 59)))
    }()

    func path(in rect: CGRect) -> Path {
        Self.mark.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: rect.width / 654, y: rect.height / 725)
        )
    }
}
