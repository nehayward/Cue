import SwiftUI

/// One finished App Store image: the backdrop, the caption and the device,
/// laid out for the shot's layout at the slot's exact size.
struct ShotView: View {
    let shot: Shot
    let model: DeviceModel
    let canvas: CGSize
    let index: Int
    let theme: Theme
    let screen: CGImage
    let companion: (model: DeviceModel, screen: CGImage)?
    let icon: CGImage?
    /// The device's width in a standard shot, as a fraction of the canvas.
    var deviceWidth: CGFloat?
    /// A standard shot's device runs off the bottom rather than shrinking to fit.
    var bleed = false
    /// The hero's turned outline, made up front (see `TiltedDevice`).
    private let heroEdge: CGImage?
    /// The backdrop, drawn up front (see `Renderer.smooth`).
    private let backdrop: CGImage

    init(shot: Shot, model: DeviceModel, canvas: CGSize, index: Int, theme: Theme, screen: CGImage,
         companion: (model: DeviceModel, screen: CGImage)?, icon: CGImage?,
         deviceWidth: CGFloat? = nil, bleed: Bool = false) throws {
        self.deviceWidth = deviceWidth
        self.bleed = bleed
        self.shot = shot
        self.model = model
        self.canvas = canvas
        self.index = index
        self.theme = theme
        self.screen = screen
        self.companion = companion
        self.icon = icon
        let layout = shot.layout ?? .standard
        let landscape = canvas.width > canvas.height
        // The light sits behind where the device is.
        let light = switch layout {
        case .hero: landscape ? UnitPoint(x: 0.745, y: 0.56) : UnitPoint(x: 0.5, y: 0.78)
        case .standard, .pair: landscape ? UnitPoint(x: 0.5, y: 0.66) : UnitPoint(x: 0.5, y: 0.64)
        }
        backdrop = try Backdrop.image(theme: theme, index: index, light: light, size: canvas)
        heroEdge = try shot.tilt.flatMap { tilt in
            shot.layout == .hero
                ? try TiltedDevice.edgeMask(
                    for: DeviceFrame(model: model, screen: screen, width: Self.heroScreenWidth(canvas), finish: Finish(theme.finish)),
                    tilt: tilt)
                : nil
        }
    }

    private var short: CGFloat { min(canvas.width, canvas.height) }
    private var landscape: Bool { canvas.width > canvas.height }
    private var titleSize: CGFloat { short * model.titleScale }
    private var margin: CGFloat { short * 0.065 }
    private var finish: Finish { Finish(theme.finish) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: backdrop, scale: 1)
            switch shot.layout ?? .standard {
            case .standard: standard
            case .hero: hero
            case .pair: pair
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
    }

    // MARK: Layouts

    /// The caption on top, the device upright under it, as large as fits.
    private var standard: some View {
        VStack(spacing: 0) {
            caption(width: canvas.width - 2 * margin)
                .padding(.top, canvas.height * (landscape ? 0.06 : 0.052))
            GeometryReader { space in
                let gap = canvas.height * 0.032
                let bottom = canvas.height * (landscape ? 0.05 : 0.03)
                let width = DeviceFrame.screenWidth(model: model, screen: screen,
                                                    fitting: CGSize(width: canvas.width * (deviceWidth ?? (landscape ? 0.84 : 0.8)),
                                                                    height: bleed ? .infinity : space.size.height - gap - bottom))
                let device = DeviceFrame(model: model, screen: screen, width: width, finish: finish)
                device
                    .deviceShadow(short)
                    .position(x: space.size.width / 2, y: gap + device.size.height / 2)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    /// The app's icon and a big title, the device large and running off the
    /// canvas: upright, or turned when the shot has a `tilt`.
    private static func heroScreenWidth(_ canvas: CGSize) -> CGFloat {
        canvas.width > canvas.height ? canvas.width * 0.47 : canvas.width * 0.74
    }

    private var heroDevice: DeviceFrame {
        DeviceFrame(model: model, screen: screen, width: Self.heroScreenWidth(canvas), finish: finish)
    }

    private var hero: some View {
        let device = heroDevice
        let text = heroText
            .frame(width: landscape ? canvas.width * 0.42 : canvas.width - 2 * margin, alignment: .leading)
            .padding(.leading, margin * (landscape ? 1.6 : 1))
        return ZStack(alignment: .topLeading) {
            if landscape {
                // Text on the left, the device on the right.
                text.frame(maxHeight: .infinity, alignment: .center)
                heroDeviceView(device).position(x: canvas.width * 0.745, y: canvas.height * 0.54)
            } else {
                // The device starts under the text, however tall the text is,
                // and runs off the bottom.
                VStack(alignment: .leading, spacing: canvas.height * 0.05) {
                    text.padding(.top, canvas.height * 0.06)
                    Color.clear
                        .frame(width: canvas.width, height: 1)
                        .overlay(alignment: .top) {
                            heroDeviceView(device)
                                .frame(width: device.size.width, height: device.size.height)
                                .offset(x: heroEdge == nil ? 0 : canvas.width * (model.kind == .tablet ? 0.02 : 0.08))
                        }
                }
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

    private func heroDeviceView(_ device: DeviceFrame) -> some View {
        ZStack {
            if let tilt = shot.tilt, let heroEdge {
                TiltedDevice(frame: device, tilt: tilt, edge: heroEdge)
                    .deviceShadow(short, x: -short * 0.015)
            } else {
                device.deviceShadow(short)
            }
        }
    }

    private var heroText: some View {
        VStack(alignment: .leading, spacing: titleSize * 0.45) {
            if let icon {
                // Drawn with its own shape: export it with its corners
                // (Icon Composer's `ictool --export-image` does).
                let side = short * (landscape ? 0.15 : 0.19)
                Image(decorative: icon, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.35), radius: side * 0.12, y: side * 0.05)
            }
            Caption(title: shot.title, subtitle: shot.subtitle, theme: theme, titleSize: titleSize * 1.32,
                    width: landscape ? canvas.width * 0.42 : canvas.width - 2 * margin, alignment: .leading)
        }
    }

    /// The caption on top, the main device on the left and its companion
    /// (the watch) overlapping it on the right.
    private var pair: some View {
        VStack(spacing: 0) {
            caption(width: canvas.width - 2 * margin)
                .padding(.top, canvas.height * (landscape ? 0.06 : 0.052))
            GeometryReader { space in
                let gap = canvas.height * 0.032
                let bottom = canvas.height * 0.03
                let width = DeviceFrame.screenWidth(model: model, screen: screen,
                                                    fitting: CGSize(width: canvas.width * 0.62,
                                                                    height: space.size.height - gap - bottom))
                let main = DeviceFrame(model: model, screen: screen, width: width, finish: finish)
                let mainCenter = CGPoint(x: canvas.width * (landscape ? 0.4 : 0.37), y: gap + main.size.height / 2)
                main
                    .deviceShadow(short)
                    .position(mainCenter)
                if let companion {
                    // To the phone's side, overlapping its edge, so the band
                    // runs beside the phone rather than over its screen.
                    let other = DeviceFrame(model: companion.model, screen: companion.screen,
                                            width: canvas.width * (landscape ? 0.17 : 0.32), finish: finish,
                                            bandReach: 0.24)
                    other
                        .deviceShadow(short, strength: 1.25)
                        .position(x: canvas.width * (landscape ? 0.78 : 0.755),
                                  y: mainCenter.y + main.size.height * (landscape ? 0.14 : 0.2))
                }
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    // MARK: Pieces

    private func caption(width: CGFloat) -> some View {
        Caption(title: shot.title, subtitle: shot.subtitle, theme: theme, titleSize: titleSize,
                width: landscape ? min(width, canvas.width * 0.7) : width)
    }
}

extension View {
    /// A device resting just above the backdrop: a tight shadow where it's
    /// closest and a wide, soft one under it.
    func deviceShadow(_ short: CGFloat, x: CGFloat = 0, strength: Double = 1) -> some View {
        self
            .shadow(color: .black.opacity(0.3 * strength), radius: short * 0.006, x: x * 0.2, y: short * 0.004)
            .shadow(color: .black.opacity(0.42 * strength), radius: short * 0.045, x: x, y: short * 0.03)
    }
}

extension DeviceFrame {
    /// The display width at which the whole device fits in `size`.
    static func screenWidth(model: DeviceModel, screen: CGImage, fitting size: CGSize) -> CGFloat {
        let aspect = CGFloat(screen.height) / CGFloat(screen.width)
        let border = 2 * (model.bezel + model.rim)
        // The border is a fraction of the display's short side.
        let shortPerWidth = min(1, aspect)
        let byWidth = size.width / (1 + border * shortPerWidth)
        let byHeight = size.height / (aspect + border * shortPerWidth)
        return max(1, min(byWidth, byHeight))
    }
}
