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
        heroEdge = shot.layout == .hero
            ? try TiltedDevice.edgeMask(
                for: DeviceFrame(model: model, screen: screen, width: Self.heroScreenWidth(canvas), finish: Finish(theme.finish)),
                tilt: shot.tilt ?? .hero)
            : nil
    }

    private var short: CGFloat { min(canvas.width, canvas.height) }
    private var landscape: Bool { canvas.width > canvas.height }
    private var titleSize: CGFloat { short * model.titleScale }
    private var margin: CGFloat { short * 0.065 }
    private var finish: Finish { Finish(theme.finish) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Backdrop(theme: theme, index: index)
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
                glow(for: device.size)
                    .position(x: space.size.width / 2, y: gap + device.size.height * 0.55)
                device
                    .shadow(color: .black.opacity(0.45), radius: short * 0.035, y: short * 0.018)
                    .position(x: space.size.width / 2, y: gap + device.size.height / 2)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }

    /// The app's icon and a big title, the device large and turned, running
    /// off the canvas.
    private static func heroScreenWidth(_ canvas: CGSize) -> CGFloat {
        canvas.width > canvas.height ? canvas.width * 0.46 : canvas.width * 0.74
    }

    private var heroDevice: DeviceFrame {
        DeviceFrame(model: model, screen: screen, width: Self.heroScreenWidth(canvas), finish: finish)
    }

    private var heroTilt: Tilt { shot.tilt ?? .hero }

    private var hero: some View {
        let device = heroDevice
        let text = heroText
            .frame(width: landscape ? canvas.width * 0.42 : canvas.width - 2 * margin, alignment: .leading)
            .padding(.leading, margin * (landscape ? 1.6 : 1))
        return ZStack(alignment: .topLeading) {
            if landscape {
                // Text on the left, the device on the right.
                text.frame(maxHeight: .infinity, alignment: .center)
                heroDeviceView(device).position(x: canvas.width * 0.75, y: canvas.height * 0.58)
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
                                .offset(x: canvas.width * 0.08)
                        }
                }
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
    }

    private func heroDeviceView(_ device: DeviceFrame) -> some View {
        ZStack {
            glow(for: device.size).offset(y: device.size.height * 0.15)
            TiltedDevice(frame: device, tilt: heroTilt, edge: heroEdge!)
                .shadow(color: .black.opacity(0.38), radius: short * 0.04, x: -short * 0.015, y: short * 0.035)
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
                                                    fitting: CGSize(width: canvas.width * 0.64,
                                                                    height: space.size.height - gap - bottom))
                let main = DeviceFrame(model: model, screen: screen, width: width, finish: finish)
                let mainCenter = CGPoint(x: canvas.width * (landscape ? 0.4 : 0.39), y: gap + main.size.height / 2)
                glow(for: main.size).position(x: canvas.width / 2, y: mainCenter.y)
                main
                    .shadow(color: .black.opacity(0.45), radius: short * 0.035, y: short * 0.018)
                    .position(mainCenter)
                if let companion {
                    let other = DeviceFrame(model: companion.model, screen: companion.screen,
                                            width: canvas.width * (landscape ? 0.17 : 0.34), finish: finish)
                    other
                        .shadow(color: .black.opacity(0.55), radius: short * 0.04, y: short * 0.02)
                        .position(x: canvas.width * (landscape ? 0.78 : 0.76),
                                  y: mainCenter.y + main.size.height * (landscape ? 0.14 : 0.24))
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

    /// A soft light behind the device, in the shot's palette colour.
    private func glow(for size: CGSize) -> some View {
        let palette = theme.palette.isEmpty ? [theme.base] : theme.palette
        let color = palette[index % palette.count]
        return Ellipse()
            .fill(color.color.opacity(0.55))
            .frame(width: size.width * 1.05, height: size.height * 0.75)
            .blur(radius: short * 0.12)
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
