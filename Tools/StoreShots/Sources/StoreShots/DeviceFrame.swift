import SwiftUI

/// A screenshot inside a drawn device: metal rim, black bezel, the display's
/// rounded corners, the Dynamic Island, buttons. Everything is drawn here, so
/// a model with no product image (the iPhone Duo) gets a frame too.
struct DeviceFrame: View {
    let model: DeviceModel
    let screen: CGImage
    /// The display's width on the canvas.
    let width: CGFloat
    let finish: Finish

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

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.kind == .watch { band }
            buttons
            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                .fill(finish.metal)
                .overlay {
                    RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                        .strokeBorder(finish.highlight, lineWidth: max(1, rim * 0.22))
                }
                .frame(width: size.width, height: size.height)
            RoundedRectangle(cornerRadius: screenRadius + bezel, style: .continuous)
                .fill(.black)
                .frame(width: size.width - 2 * rim, height: size.height - 2 * rim)
                .offset(x: rim, y: rim)
            Image(decorative: screen, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: screenSize.width, height: screenSize.height)
                .clipShape(RoundedRectangle(cornerRadius: screenRadius, style: .continuous))
                .offset(x: rim + bezel, y: rim + bezel)
            if model.kind == .phone { island }
            if model.kind == .foldable { crease }
            if model.kind == .tablet { camera }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
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
            .fill(Color(white: 0.12))
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
            button(edge: .trailing, from: 0.53, to: 0.58, proud: 0.35)
        case .watch:
            // The Digital Crown, ridged, and the side button below it.
            let crownHeight = size.height * 0.2
            RoundedRectangle(cornerRadius: rim * 0.5, style: .continuous)
                .fill(finish.metal)
                .overlay {
                    VStack(spacing: crownHeight * 0.06) {
                        ForEach(0..<9, id: \.self) { _ in
                            Rectangle().fill(.black.opacity(0.28)).frame(height: max(1, crownHeight * 0.025))
                        }
                    }
                    .padding(.vertical, crownHeight * 0.12)
                }
                .frame(width: rim * 2.6, height: crownHeight)
                .position(x: size.width + rim * 0.4, y: size.height * 0.3)
            button(edge: .trailing, from: 0.5, to: 0.72, proud: 0.45)
        default:
            EmptyView()
        }
    }

    /// A button proud of the rim along one edge, between two fractions of the
    /// device's height.
    private func button(edge: HorizontalEdge, from: CGFloat, to: CGFloat, proud: CGFloat = 0.6) -> some View {
        let length = size.height * (to - from)
        let thickness = rim * 1.6
        let out = rim * proud
        let x = edge == .leading ? -out + thickness / 2 : size.width + out - thickness / 2
        return RoundedRectangle(cornerRadius: thickness / 2, style: .continuous)
            .fill(finish.metal)
            .frame(width: thickness, height: length)
            .position(x: x, y: size.height * from + length / 2)
    }

    /// A sport band, above and below the case, fading out as it goes.
    private var band: some View {
        let bandWidth = size.width * 0.74
        let reach = size.height * 0.42
        return RoundedRectangle(cornerRadius: bandWidth * 0.12, style: .continuous)
            .fill(LinearGradient(stops: [
                .init(color: finish.band.opacity(0), location: 0),
                .init(color: finish.band, location: 0.3),
                .init(color: finish.band, location: 0.7),
                .init(color: finish.band.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom))
            .frame(width: bandWidth, height: size.height + 2 * reach)
            .position(x: size.width / 2, y: size.height / 2)
    }
}

/// The device's metal.
struct Finish {
    let metal: LinearGradient
    let highlight: LinearGradient
    let edge: Color
    let band: Color

    init(_ name: String?) {
        let stops: [Color]
        switch name {
        case "silver":
            stops = [Color(white: 0.93), Color(white: 0.74), Color(white: 0.6), Color(white: 0.8), Color(white: 0.95)]
            edge = Color(white: 0.66)
            band = Color(white: 0.85)
        case "midnight":
            stops = [Color(red: 0.3, green: 0.34, blue: 0.42), Color(red: 0.13, green: 0.16, blue: 0.22),
                     Color(red: 0.08, green: 0.1, blue: 0.15), Color(red: 0.18, green: 0.21, blue: 0.28),
                     Color(red: 0.34, green: 0.38, blue: 0.47)]
            edge = Color(red: 0.24, green: 0.27, blue: 0.34)
            band = Color(red: 0.12, green: 0.14, blue: 0.2)
        default:
            stops = [Color(white: 0.42), Color(white: 0.2), Color(white: 0.12), Color(white: 0.24), Color(white: 0.48)]
            edge = Color(white: 0.3)
            band = Color(white: 0.16)
        }
        metal = LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
        highlight = LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.04), .white.opacity(0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
