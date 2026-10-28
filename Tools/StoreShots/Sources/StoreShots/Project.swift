import Foundation
import SwiftUI

/// One app's App Store art: its look, the devices it ships on, the shots and
/// the previews, read from a JSON file. Paths in it are relative to the file.
struct Project: Decodable {
    /// The app's name, for messages and the contact sheet.
    var app: String
    /// For `shoot --launch`: the app to relaunch with a shot's arguments.
    var bundleID: String?
    /// Launch arguments every `shoot --launch` passes, before the shot's own
    /// (a Debug build's screenshot switches, say).
    var launch: [String]?
    /// The app icon (a square PNG), drawn above the hero's title.
    var icon: String?
    /// Raw screenshots, one folder per device: `<raw>/<device>/<shot>.png`.
    var raw: String?
    /// Screen recordings for the previews: `<clips>/<device>/<clip>.mov`.
    var clips: String?
    /// Finished art: `<output>/<device>/NN-<shot>.png` and the previews.
    var output: String?
    var theme: Theme
    /// Keyed by a short name (`iphone`, `duo`, `ipad`, `watch`), used for the
    /// raw folders and on the command line.
    var devices: [String: DeviceSetup]
    var shots: [Shot]
    var previews: [PreviewSpec]?
    /// Wide art for the product page's header and the search results.
    var banners: [Banner]?
}

struct Theme: Decodable {
    /// The backdrop's colour.
    var base: HexColor
    /// The colour the backdrop is lit with behind the device; with several,
    /// each shot takes the next in turn.
    var palette: [HexColor]
    var title: HexColor?
    var subtitle: HexColor?
    /// Words in a title wrapped in `*asterisks*` take this colour.
    var accent: HexColor?
    /// `bold` (default), `heavy`, `semibold` or `black`.
    var titleWeight: String?
    /// `rounded` (default, SF Pro Rounded), `default` (SF Pro) or `serif`.
    var design: String?
    /// The device's metal: `graphite` (default), `silver` or `midnight`.
    var finish: String?
}

struct DeviceSetup: Decodable {
    /// A model from the catalog (`storeshots devices` lists them).
    var model: String
    /// The app `shoot --launch` relaunches on this device, when it isn't the
    /// project's (a watch app has a bundle ID of its own).
    var bundleID: String?
    /// The simulator `shoot` and `record` use, by name.
    var simulator: String?
    /// `simctl --display` for a device with two screens: the iPhone Duo's
    /// inner display, by its screen UUID or name.
    var display: String?
    /// The art in landscape. Unset, it follows the raw screenshots.
    var landscape: Bool?
    /// The raw screenshot as it is, no frame or caption (Apple Watch: the
    /// store draws the watch around it).
    var bare: Bool?
    /// 9:41, full battery and signal, on iOS simulators. On by default.
    var statusBar: Bool?
    /// The device's width in standard shots, as a fraction of the canvas.
    var deviceWidth: Double?
    /// Standard shots let the device run off the bottom at `deviceWidth`
    /// rather than shrink to fit: for screens whose lower part is empty.
    /// A shot's own `bleed` wins.
    var bleed: Bool?
}

enum LayoutKind: String, Decodable {
    /// Caption above the device, the device upright.
    case standard
    /// The app's icon and a big title, the device tilted and large.
    case hero
    /// Two devices side by side (the iPhone with its watch app).
    case pair
}

struct Shot: Decodable {
    var name: String
    var layout: LayoutKind?
    var title: String
    var subtitle: String?
    /// The devices that get this shot. Unset: every device with a raw
    /// screenshot named after it.
    var devices: [String]?
    /// The hero's device turned in 3D (`Tilt.hero` is a good start);
    /// unset, it stands upright.
    var tilt: Tilt?
    /// The second device in a pair.
    var companion: Companion?
    /// `shoot --launch`: launch arguments that open the app on this shot.
    var launch: [String]?
    /// Seconds to wait after launching before the screenshot.
    var wait: Double?
    /// The device runs off the bottom rather than shrinking to fit (see
    /// `DeviceSetup.bleed`), for a screen whose lower part is empty.
    var bleed: Bool?
    /// Per device: another title, subtitle, layout or raw screenshot.
    var overrides: [String: ShotOverride]?

    func resolved(for device: String) -> Shot {
        guard let override = overrides?[device] else { return self }
        var shot = self
        if let title = override.title { shot.title = title }
        if let subtitle = override.subtitle { shot.subtitle = subtitle }
        if let layout = override.layout { shot.layout = layout }
        if let tilt = override.tilt { shot.tilt = tilt }
        if let bleed = override.bleed { shot.bleed = bleed }
        return shot
    }

    func screenName(for device: String) -> String {
        overrides?[device]?.screen ?? name
    }
}

struct ShotOverride: Decodable {
    var title: String?
    var subtitle: String?
    var layout: LayoutKind?
    var tilt: Tilt?
    var bleed: Bool?
    /// Another raw screenshot's name in the device's folder.
    var screen: String?
}

struct Companion: Decodable {
    /// The companion's device key, for its frame and its raw folder.
    var device: String
    /// The companion's raw screenshot in that folder.
    var screen: String
}

/// A rotation about an axis, as SwiftUI's `rotation3DEffect` takes it.
struct Tilt: Decodable {
    var angle: Double
    var axis: [Double]
    /// How strongly nearer parts grow: 0 is flat, 1 SwiftUI's default.
    var perspective: Double?

    static let hero = Tilt(angle: 24, axis: [0.22, -1, 0.08], perspective: 0.55)
}

/// A product page header or search results asset: a caption over a fan of
/// devices that runs off the bottom, the middle one front and largest.
struct Banner: Decodable {
    /// The file's name, without extension: `<output>/banners/<name>.png`.
    var name: String
    /// Width and height in pixels.
    var size: [Int]
    var title: String
    var subtitle: String?
    /// Width and height, centred, that the caption and the devices' faces
    /// stay inside: a universal asset is cropped to 21:9 for the header and
    /// to 3:2 for search results. Unset: the whole canvas.
    var safe: [Int]?
    /// The fan, left to right, an odd number: the middle device upright,
    /// the others smaller and turned towards it.
    var devices: [BannerDevice]
    /// A device in front of the fan, between the middle and the next on its
    /// right (the watch).
    var companion: BannerDevice?
    /// Which palette colour lights the backdrop.
    var palette: Int?
}

struct BannerDevice: Decodable {
    /// The device's key, for its frame and its raw folder.
    var device: String
    /// A raw screenshot in that folder.
    var screen: String
}

struct PreviewSpec: Decodable {
    /// The movie's file name, without extension.
    var name: String
    /// The device whose recordings it shows, for its size and raw folders.
    var device: String
    /// Width and height. Unset: the model's App Preview size.
    var size: [Int]?
    var fps: Int?
    /// Seconds each push from one scene to the next takes.
    var transition: Double?
    /// The first scene swings in from a tilt.
    var tiltIn: Bool?
    /// The recordings inside the drawn device. App Store Connect wants
    /// previews to be the app's own screen, so this is for the website and
    /// social posts.
    var frame: Bool?
    /// The device sways slowly in 3D.
    var float: Bool?
    var scenes: [PreviewScene]
}

struct PreviewScene: Decodable {
    /// A recording in `<clips>/<device>/`.
    var clip: String?
    /// Or a still: a raw screenshot's name in `<raw>/<device>/`.
    var still: String?
    /// Where in the recording the scene starts, in seconds.
    var from: Double?
    var duration: Double
    /// Playback speed: 2 plays the recording twice as fast.
    var rate: Double?
    var title: String
    var subtitle: String?
}

struct HexColor: Decodable {
    var red, green, blue, alpha: Double

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let color = HexColor(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "not a #RRGGBB or #RRGGBBAA colour: \(text)"))
        }
        self = color
    }

    init?(_ text: String) {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let full = hex.count == 6 ? value << 8 | 0xFF : value
        red = Double(full >> 24 & 0xFF) / 255
        green = Double(full >> 16 & 0xFF) / 255
        blue = Double(full >> 8 & 0xFF) / 255
        alpha = Double(full & 0xFF) / 255
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    func mixed(with other: HexColor, _ amount: Double) -> HexColor {
        HexColor(red: red + (other.red - red) * amount,
                 green: green + (other.green - green) * amount,
                 blue: blue + (other.blue - blue) * amount,
                 alpha: alpha + (other.alpha - alpha) * amount)
    }

    static let white = HexColor(red: 1, green: 1, blue: 1)
}

/// The project file and the folders its paths are relative to.
struct Workspace {
    let project: Project
    let base: URL

    init(path: String) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let data = try Data(contentsOf: url)
        do {
            project = try JSONDecoder().decode(Project.self, from: data)
        } catch {
            throw Failure("\(url.lastPathComponent): \(error)")
        }
        base = url.deletingLastPathComponent()
    }

    func resolve(_ path: String) -> URL {
        URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
    }

    var rawFolder: URL { resolve(project.raw ?? "raw") }
    var clipsFolder: URL { resolve(project.clips ?? "clips") }
    var outputFolder: URL { resolve(project.output ?? "output") }

    func raw(_ device: String, _ name: String) -> URL {
        rawFolder.appendingPathComponent(device).appendingPathComponent(name + ".png")
    }

    func setup(_ key: String) throws -> DeviceSetup {
        guard let setup = project.devices[key] else {
            throw Failure("no device \(key) in the project (it has \(project.devices.keys.sorted().joined(separator: ", ")))")
        }
        return setup
    }

    func model(_ key: String) throws -> DeviceModel {
        let setup = try setup(key)
        guard let model = DeviceModel.catalog[setup.model] else {
            throw Failure("\(key): no model \(setup.model); `storeshots devices` lists them")
        }
        return model
    }

    /// The shots this device gets, in order, each with its raw screenshot.
    func shots(for device: String) -> [(shot: Shot, screen: URL)] {
        project.shots.compactMap { shot in
            if let devices = shot.devices, !devices.contains(device) { return nil }
            let screen = raw(device, shot.screenName(for: device))
            guard FileManager.default.fileExists(atPath: screen.path) else { return nil }
            return (shot.resolved(for: device), screen)
        }
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
