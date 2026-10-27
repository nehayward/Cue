import SwiftUI

/// A screenshot inside a drawn device: a machined metal rim with a polished
/// chamfer, the black glass round the display with a little glare, the
/// display's rounded corners, the Dynamic Island, shaded buttons. Everything
/// is drawn here, so a model with no product image (the iPhone Duo) gets a
/// frame too.
struct DeviceFrame: View {
    let model: DeviceModel
    let screen: CGImage
    /// The display's width on the canvas.
    let width: CGFloat
    let finish: Finish
    /// How far a watch's band reaches past the case, as a fraction of the
    /// case's height, before it has faded out.
    var bandReach: CGFloat = 0.42

    var screenSize: CGSize {
        CGSize(width: width, height: width * CGFloat(screen.height) / CGFloat(screen.width))
    }
    var landscape: Bool { screen.width > screen.height }
    /// The display's short side, the unit every measurement is a fraction of.
    var unit: CGFloat { min(screenSize.width, screenSize.height) }
    var bezel: CGFloat { unit * model.bezel }
    var rim: CGFloat { unit * model.rim }
    var screenRadius: CGFloat { unit * model.screenRadius }
    var size: CGSize {
        CGSize(width: screenSize.width + 2 * (bezel + rim), height: screenSize.height + 2 * (bezel + rim))
    }
    var outerRadius: CGFloat { screenRadius + bezel + rim }
    private var glassRadius: CGFloat { screenRadius + bezel }
    private var glassSize: CGSize { CGSize(width: size.width - 2 * rim, height: size.height - 2 * rim) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.kind == .watch { band }
            buttons
            metal
            glass
            Image(decorative: screen, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: screenSize.width, height: screenSize.height)
                .clipShape(RoundedRectangle(cornerRadius: screenRadius, style: .continuous))
                .offset(x: rim + bezel, y: rim + bezel)
            if model.kind == .phone { island }
            if model.kind == .foldable { crease }
            if model.kind == .tablet { camera }
            glare
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// The metal seen from the front: its colour, the light it catches as it
    /// turns round the corners, a dark line where its side curves away and a
    /// bright chamfer where it meets the glass.
    private var metal: some View {
        let outline = RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
        let chamferInset = rim * 0.58
        let chamfer = RoundedRectangle(cornerRadius: outerRadius - chamferInset, style: .continuous)
        return outline
            .fill(finish.metal)
            .overlay { outline.fill(finish.reflections) }
            .overlay { outline.strokeBorder(finish.outerEdge, lineWidth: max(1, rim * 0.16)) }
            .overlay {
                chamfer
                    .strokeBorder(finish.chamfer, lineWidth: max(1, rim * 0.26))
                    .padding(chamferInset)
            }
            .frame(width: size.width, height: size.height)
    }

    /// The black glass round the display, lit a touch at the top, with a
    /// faint line where its edge catches the light.
    private var glass: some View {
        let shape = RoundedRectangle(cornerRadius: glassRadius, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [Color(white: 0.075), Color(white: 0.02), Color(white: 0.035)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.05), .white.opacity(0.12)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing),
                                   lineWidth: max(1, unit * 0.0025))
            }
            .frame(width: glassSize.width, height: glassSize.height)
            .offset(x: rim, y: rim)
    }

    /// A soft sheen across the front glass from the top left, faint enough
    /// to leave the screen as it is.
    private var glare: some View {
        RoundedRectangle(cornerRadius: glassRadius, style: .continuous)
            .fill(LinearGradient(stops: [
                .init(color: .white.opacity(model.kind == .watch ? 0.1 : 0.06), location: 0),
                .init(color: .white.opacity(0.015), location: 0.34),
                .init(color: .clear, location: 0.5),
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: glassSize.width, height: glassSize.height)
            .offset(x: rim, y: rim)
    }

    /// Where the Dynamic Island sits, from the frame's top left: 126 × 37 pt
    /// on a 402 pt display, 11 pt from its edge.
    var islandFrame: CGRect {
        let across = landscape ? screenSize.height : screenSize.width
        let long = across * 0.315, short = across * 0.093, inset = across * 0.0275
        return landscape
            ? CGRect(x: rim + bezel + inset, y: (size.height - long) / 2, width: short, height: long)
            : CGRect(x: (size.width - long) / 2, y: rim + bezel + inset, width: long, height: short)
    }

    private var island: some View {
        let frame = islandFrame
        return Capsule()
            .fill(.black)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }

    /// The fold down the middle of an open book-style foldable.
    private var crease: some View {
        let vertical = landscape
        let thickness = unit * 0.012
        return Rectangle()
            .fill(LinearGradient(colors: [.clear, .white.opacity(0.06), .black.opacity(0.18), .white.opacity(0.06), .clear],
                                 startPoint: vertical ? .leading : .top, endPoint: vertical ? .trailing : .bottom))
            .frame(width: vertical ? thickness : screenSize.width, height: vertical ? screenSize.height : thickness)
            .position(x: size.width / 2, y: size.height / 2)
    }

    /// The front camera, in the bezel of the long edge that's on top in landscape.
    private var camera: some View {
        let diameter = bezel * 0.22
        return Circle()
            .fill(RadialGradient(colors: [Color(red: 0.14, green: 0.16, blue: 0.24), Color(white: 0.04)],
                                 center: .init(x: 0.38, y: 0.35), startRadius: 0, endRadius: diameter * 0.6))
            .frame(width: diameter, height: diameter)
            .position(landscape ? CGPoint(x: size.width / 2, y: rim + bezel / 2)
                                : CGPoint(x: size.width - rim - bezel / 2, y: size.height / 2))
    }

    @ViewBuilder private var buttons: some View {
        switch model.kind {
        case .phone where !landscape:
            // Left: Action button, volume up, volume down. Right: side button,
            // Camera Control.
            button(edge: .leading, from: 0.18, to: 0.215)
            button(edge: .leading, from: 0.255, to: 0.315)
            button(edge: .leading, from: 0.335, to: 0.395)
            button(edge: .trailing, from: 0.27, to: 0.37)
            button(edge: .trailing, from: 0.53, to: 0.58, proud: 0.3)
        case .tablet:
            // The top button and the volume buttons on the long side.
            if !landscape {
                button(edge: .leading, from: 0.78, to: 0.87, proud: 0.45, horizontal: true)
                button(edge: .trailing, from: 0.07, to: 0.11, proud: 0.45)
                button(edge: .trailing, from: 0.12, to: 0.16, proud: 0.45)
            }
        case .watch:
            crown
            button(edge: .trailing, from: 0.5, to: 0.72, proud: 0.4)
        default:
            EmptyView()
        }
    }

    /// The Digital Crown: a knurled cylinder seen from the side, lit along
    /// its top.
    private var crown: some View {
        let height = size.height * 0.19
        let protrusion = rim * 2.6
        let ridges = 11
        return RoundedRectangle(cornerRadius: protrusion * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [finish.dark, finish.light, finish.mid, finish.mid, finish.dark],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                VStack(spacing: 0) {
                    ForEach(0..<ridges, id: \.self) { _ in
                        VStack(spacing: 0) {
                            Rectangle().fill(.white.opacity(0.12)).frame(height: max(0.5, height * 0.012))
                            Spacer(minLength: 0)
                            Rectangle().fill(.black.opacity(0.35)).frame(height: max(1, height * 0.02))
                        }
                    }
                }
                .padding(.vertical, height * 0.06)
                .padding(.leading, protrusion * 0.3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: protrusion * 0.28, style: .continuous)
                    .strokeBorder(.black.opacity(0.35), lineWidth: max(1, rim * 0.08))
            }
            .frame(width: protrusion + rim, height: height)
            .position(x: size.width + protrusion / 2 - rim * 0.5, y: size.height * 0.3)
    }

    /// A button proud of the rim along one edge, between two fractions of the
    /// device's height (or width, `horizontal`, along the top edge), shaded
    /// as a rounded bar.
    private func button(edge: HorizontalEdge, from: CGFloat, to: CGFloat, proud: CGFloat = 0.6,
                        horizontal: Bool = false) -> some View {
        let along = horizontal ? size.width : size.height
        let length = along * (to - from)
        let thickness = rim * 1.6
        let out = rim * proud
        let shading = LinearGradient(colors: [finish.dark, finish.mid, finish.light, finish.mid, finish.dark],
                                     startPoint: horizontal ? .top : .leading, endPoint: horizontal ? .bottom : .trailing)
        let bar = RoundedRectangle(cornerRadius: thickness / 2, style: .continuous)
            .fill(shading)
            .overlay {
                RoundedRectangle(cornerRadius: thickness / 2, style: .continuous)
                    .strokeBorder(.black.opacity(0.3), lineWidth: max(0.5, rim * 0.06))
            }
        if horizontal {
            return bar
                .frame(width: length, height: thickness)
                .position(x: along * from + length / 2, y: -out + thickness / 2)
        }
        let x = edge == .leading ? -out + thickness / 2 : size.width + out - thickness / 2
        return bar
            .frame(width: thickness, height: length)
            .position(x: x, y: along * from + length / 2)
    }

    /// A sport band above and below the case: rounded across its width,
    /// darker where it tucks under the case, fading out as it goes.
    private var band: some View {
        let bandWidth = size.width * 0.62
        let reach = size.height * bandReach
        let tuck = size.height * 0.12
        return VStack(spacing: 0) {
            strap(width: bandWidth, length: reach + tuck, top: true)
            Color.clear.frame(height: size.height - 2 * tuck)
            strap(width: bandWidth, length: reach + tuck, top: false)
        }
        .frame(width: bandWidth)
        .position(x: size.width / 2, y: size.height / 2)
    }

    private func strap(width: CGFloat, length: CGFloat, top: Bool) -> some View {
        let toward = top ? UnitPoint.bottom : .top
        let away = top ? UnitPoint.top : .bottom
        return Rectangle()
            .fill(LinearGradient(stops: [
                .init(color: finish.band.mix(with: .black, by: 0.7), location: 0),
                .init(color: finish.band, location: 0.12),
                .init(color: finish.band.mix(with: .white, by: 0.16), location: 0.36),
                .init(color: finish.band.mix(with: .white, by: 0.05), location: 0.62),
                .init(color: finish.band.mix(with: .black, by: 0.25), location: 0.86),
                .init(color: finish.band.mix(with: .black, by: 0.7), location: 1),
            ], startPoint: .leading, endPoint: .trailing))
            // The case's shadow on the band where it comes out from under it.
            .overlay {
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.38),
                ], startPoint: toward, endPoint: away)
            }
            .mask {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.25),
                    .init(color: .black.opacity(0.35), location: 0.6),
                    .init(color: .clear, location: 1),
                ], startPoint: toward, endPoint: away)
            }
            .frame(width: width, height: length)
    }
}

/// The device's metal.
struct Finish {
    /// The metal's colour across the front.
    let metal: LinearGradient
    /// Light and shade the rim catches as it turns round the corners.
    let reflections: AngularGradient
    /// Where the side curves away, at the outline.
    let outerEdge: Color
    /// The polished chamfer at the glass.
    let chamfer: LinearGradient
    /// The side of a turned device (`TiltedDevice`).
    let edge: Color
    let band: Color
    /// Tones for the buttons and the crown, shaded as rounded metal.
    let dark: Color
    let mid: Color
    let light: Color

    init(_ name: String?) {
        let stops: [Color]
        switch name {
        case "silver":
            stops = [Color(white: 0.9), Color(white: 0.72), Color(white: 0.6), Color(white: 0.78), Color(white: 0.92)]
            edge = Color(white: 0.66)
            band = Color(white: 0.86)
            (dark, mid, light) = (Color(white: 0.5), Color(white: 0.74), Color(white: 0.95))
            outerEdge = Color(white: 0.35).opacity(0.8)
        case "midnight":
            stops = [Color(red: 0.3, green: 0.34, blue: 0.42), Color(red: 0.14, green: 0.17, blue: 0.23),
                     Color(red: 0.09, green: 0.11, blue: 0.16), Color(red: 0.18, green: 0.21, blue: 0.28),
                     Color(red: 0.33, green: 0.37, blue: 0.46)]
            edge = Color(red: 0.24, green: 0.27, blue: 0.34)
            band = Color(red: 0.11, green: 0.13, blue: 0.19)
            (dark, mid, light) = (Color(red: 0.07, green: 0.08, blue: 0.12), Color(red: 0.2, green: 0.23, blue: 0.3),
                                  Color(red: 0.42, green: 0.46, blue: 0.55))
            outerEdge = .black.opacity(0.7)
        default:
            stops = [Color(white: 0.38), Color(white: 0.21), Color(white: 0.14), Color(white: 0.23), Color(white: 0.42)]
            edge = Color(white: 0.3)
            band = Color(white: 0.17)
            (dark, mid, light) = (Color(white: 0.09), Color(white: 0.22), Color(white: 0.46))
            outerEdge = .black.opacity(0.75)
        }
        metal = LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
        reflections = AngularGradient(stops: [
            .init(color: .white.opacity(0.05), location: 0),
            .init(color: .white.opacity(0.3), location: 0.07),
            .init(color: .clear, location: 0.16),
            .init(color: .black.opacity(0.22), location: 0.3),
            .init(color: .clear, location: 0.42),
            .init(color: .white.opacity(0.18), location: 0.57),
            .init(color: .clear, location: 0.66),
            .init(color: .black.opacity(0.25), location: 0.8),
            .init(color: .clear, location: 0.9),
            .init(color: .white.opacity(0.05), location: 1),
        ], center: .center, angle: .degrees(200))
        chamfer = LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.18), .white.opacity(0.08),
                                          .white.opacity(0.3), .white.opacity(0.6)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
