import SwiftUI

/// A device turned in 3D, with its edge showing: copies of its turned
/// outline, stepped back along the direction its back faces, under the front.
///
/// The outline is turned once, into a bitmap (`edgeMask`), and the copies are
/// that bitmap moved: ImageRenderer draws a few dozen 3D-turned shapes as
/// black slabs.
struct TiltedDevice: View {
    let frame: DeviceFrame
    let tilt: Tilt
    /// `edgeMask(for:tilt:)`, made before rendering.
    let edge: CGImage

    var body: some View {
        let size = frame.size
        let depth = frame.unit * frame.model.depth
        let steps = min(40, max(10, Int(depth / 2.5)))
        let back = Self.backDirection(tilt)
        let padded = CGSize(width: size.width * Self.padding, height: size.height * Self.padding)
        ZStack {
            ForEach(Array(stride(from: steps, through: 1, by: -1)), id: \.self) { step in
                let fraction = CGFloat(step) / CGFloat(steps)
                Image(decorative: edge, scale: 1)
                    .renderingMode(.template)
                    .resizable()
                    .foregroundStyle(edgeShade(fraction))
                    .frame(width: padded.width, height: padded.height)
                    .offset(x: back.dx * depth * fraction, y: back.dy * depth * fraction)
            }
            frame.modifier(TiltEffect(tilt: tilt))
        }
        .frame(width: size.width, height: size.height)
    }

    /// How much room round the device the turned outline gets.
    static let padding: CGFloat = 1.6

    /// The device's outline, turned, centred in a canvas `padding` times its size.
    static func edgeMask(for frame: DeviceFrame, tilt: Tilt) throws -> CGImage {
        let size = frame.size
        let padded = CGSize(width: (size.width * padding).rounded(), height: (size.height * padding).rounded())
        let outline = RoundedRectangle(cornerRadius: frame.outerRadius, style: .continuous)
            .fill(.white)
            .frame(width: size.width, height: size.height)
            .modifier(TiltEffect(tilt: tilt))
            .frame(width: padded.width, height: padded.height)
        let mask = try Renderer.image(outline, size: padded)
        if let path = ProcessInfo.processInfo.environment["DUMP_EDGE"] { try Renderer.write(mask, to: URL(fileURLWithPath: path)) }
        return mask
    }

    /// The machined edge: bright where it meets the front, darker towards the back.
    private func edgeShade(_ fraction: CGFloat) -> Color {
        frame.finish.edge.mix(with: .white, by: max(0, 0.4 - fraction * 0.7))
    }

    /// Where the device's back lands on screen, per unit of depth: the back
    /// (0, 0, -1) turned about the tilt's axis (Rodrigues).
    static func backDirection(_ tilt: Tilt) -> CGVector {
        let length = sqrt(tilt.axis.reduce(0) { $0 + $1 * $1 })
        guard length > 0, tilt.axis.count == 3 else { return .zero }
        let (ax, ay, az) = (tilt.axis[0] / length, tilt.axis[1] / length, tilt.axis[2] / length)
        let theta = tilt.angle * .pi / 180
        let (vx, vy, vz) = (0.0, 0.0, -1.0)
        let cross = (ay * vz - az * vy, az * vx - ax * vz, ax * vy - ay * vx)
        let dot = ax * vx + ay * vy + az * vz
        let x = vx * cos(theta) + cross.0 * sin(theta) + ax * dot * (1 - cos(theta))
        let y = vy * cos(theta) + cross.1 * sin(theta) + ay * dot * (1 - cos(theta))
        return CGVector(dx: x, dy: y)
    }
}

struct TiltEffect: ViewModifier {
    let tilt: Tilt

    func body(content: Content) -> some View {
        let axis = tilt.axis.count == 3 ? tilt.axis : [0, 1, 0]
        content.rotation3DEffect(.degrees(tilt.angle), axis: (x: axis[0], y: axis[1], z: axis[2]),
                                 perspective: tilt.perspective ?? 0.55)
    }
}
