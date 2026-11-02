import SwiftUI

/// A product page header or search results asset: the caption centred at
/// the top, under it a row of upright devices running off the bottom (the
/// middle one largest and highest, each step out a little smaller and
/// lower), and a companion in front. Everything that matters stays inside `safe`.
struct BannerView: View {
    let banner: Banner
    let canvas: CGSize
    let safe: CGRect
    let theme: Theme
    let fan: [Device]
    let companion: DeviceFrame?
    /// The caption, drawn up front so the fan can start under it.
    private let caption: CGImage
    private let captionTop: CGFloat
    /// The backdrop, drawn up front (see `Renderer.smooth`).
    private let backdrop: CGImage

    struct Device {
        let frame: DeviceFrame
        let center: CGPoint
        /// How far it sits back: 0 for the middle, more for each step out.
        let depth: Int
    }

    init(banner: Banner, theme: Theme, devices: [(model: DeviceModel, screen: CGImage)],
         companion: (model: DeviceModel, screen: CGImage)?) throws {
        guard banner.size.count == 2 else { throw Failure("\(banner.name): size is [width, height]") }
        guard devices.count % 2 == 1 else { throw Failure("\(banner.name): the fan needs an odd number of devices") }
        canvas = CGSize(width: banner.size[0], height: banner.size[1])
        let safeSize = banner.safe.map { CGSize(width: $0[0], height: $0[1]) } ?? canvas
        safe = CGRect(x: (canvas.width - safeSize.width) / 2, y: (canvas.height - safeSize.height) / 2,
                      width: safeSize.width, height: safeSize.height)
        self.banner = banner
        self.theme = theme

        // A wide canvas takes the caption on one line; a squarer one may wrap.
        let wide = safe.width / safe.height > 1.9
        let titleSize = safe.height * (wide ? 0.095 : 0.075)
        let captionWidth = safe.width * (wide ? 0.8 : 0.86)
        caption = try Renderer.image(
            Caption(title: banner.title, subtitle: banner.subtitle, theme: theme, titleSize: titleSize, width: captionWidth)
                .frame(width: captionWidth),
            size: CGSize(width: captionWidth, height: safe.height * 0.4), fitting: true)
        captionTop = safe.minY + safe.height * (wide ? 0.08 : 0.06)
        let top = captionTop + CGFloat(caption.height) + safe.height * (wide ? 0.07 : 0.06)

        // Steps out from the middle: size and how much lower it starts, as
        // fractions of its own height. Centre to centre, in the middle
        // device's widths, they sit side by side with a gap between.
        let scales: [CGFloat] = [1, 0.9, 0.8]
        let drops: [CGFloat] = [0, 0.035, 0.07]
        let gap: CGFloat = 0.07
        let middle = devices.count / 2
        guard middle < scales.count else { throw Failure("\(banner.name): five devices at most in the row") }
        var offsets: [CGFloat] = [0]
        for depth in scales.indices.dropFirst() {
            offsets.append(offsets[depth - 1] + scales[depth - 1] / 2 + gap + scales[depth] / 2)
        }
        let outer = offsets[middle] + scales[middle] / 2
        let model = devices[middle].model
        let border = 2 * (model.bezel + model.rim)
        let aspect = CGFloat(devices[middle].screen.height) / CGFloat(devices[middle].screen.width)
        // As wide as the safe area takes, but showing at least half the
        // middle device.
        let deviceWidth = min(safe.width * 0.98 / (2 * outer),
                              (canvas.height - top) / ((aspect + border) / (1 + border) * 0.5))
        let screenWidth = deviceWidth / (1 + border)
        let finish = Finish(theme.finish)

        var fan: [Device] = []
        for (index, device) in devices.enumerated() {
            let step = index - middle
            let depth = abs(step)
            let frame = DeviceFrame(model: device.model, screen: device.screen,
                                    width: screenWidth * scales[depth], finish: finish)
            let center = CGPoint(x: canvas.width / 2 + CGFloat(step.signum()) * offsets[depth] * deviceWidth,
                                 y: top + frame.size.height / 2 + drops[depth] * frame.size.height)
            fan.append(Device(frame: frame, center: center, depth: depth))
        }
        // Drawn from the outside in, so the middle is on top.
        self.fan = fan.sorted { $0.depth > $1.depth }

        backdrop = try Backdrop.image(theme: theme, index: banner.palette ?? 0,
                                      light: UnitPoint(x: 0.5, y: (top + (canvas.height - top) * 0.35) / canvas.height),
                                      size: canvas)
        self.companion = companion.map {
            DeviceFrame(model: $0.model, screen: $0.screen, width: screenWidth * 0.46, finish: finish, bandReach: 0.24)
        }
    }

    /// The unit shadows are sized by: a device's width, so they're as soft
    /// as in the screenshots, whatever the canvas.
    private var short: CGFloat { fan.last.map { $0.frame.size.width * 1.3 } ?? min(safe.width, safe.height) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: backdrop, scale: 1)
            ForEach(Array(fan.enumerated()), id: \.offset) { _, device in
                deviceView(device)
            }
            if let companion, let middle = fan.last {
                // In front of the gap between the middle and the next on its
                // right, low enough to sit over the screens' lower half but
                // inside the safe area.
                let y = min(middle.center.y + middle.frame.size.height * 0.12,
                            safe.maxY - companion.size.height * 0.62)
                companion
                    .deviceShadow(short, strength: 0.8)
                    .position(x: middle.center.x + middle.frame.size.width * 0.66, y: y)
            }
            Image(decorative: caption, scale: 1)
                .position(x: canvas.width / 2, y: captionTop + CGFloat(caption.height) / 2)
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
    }

    private func deviceView(_ device: Device) -> some View {
        device.frame
            .deviceShadow(short, strength: 0.4)
            .position(device.center)
    }
}
