import SwiftUI

/// The background behind a shot: the theme's dark base with one soft light
/// in the shot's palette colour, centred behind the devices. Drawn through
/// `Renderer.smooth`, so the falloff has no bands.
struct Backdrop: View {
    let theme: Theme
    /// The shot's place in the set, for its palette colour.
    let index: Int
    /// Where the light is brightest, as a fraction of the canvas.
    var light = UnitPoint(x: 0.5, y: 0.62)

    var body: some View {
        let palette = theme.palette.isEmpty ? [theme.base] : theme.palette
        let color = palette[index % palette.count].color
        ZStack {
            theme.base.color
            EllipticalGradient(stops: [
                .init(color: color.opacity(0.42), location: 0),
                .init(color: color.opacity(0.2), location: 0.28),
                .init(color: color.opacity(0.06), location: 0.6),
                .init(color: color.opacity(0), location: 1),
            ], center: light, startRadiusFraction: 0, endRadiusFraction: 0.85)
        }
    }

    /// The backdrop as an opaque image the size of the canvas.
    static func image(theme: Theme, index: Int, light: UnitPoint, size: CGSize) throws -> CGImage {
        try Renderer.smooth(Backdrop(theme: theme, index: index, light: light), size: size)
    }
}
