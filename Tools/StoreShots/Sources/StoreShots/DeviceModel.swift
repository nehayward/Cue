import CoreGraphics

/// A device App Store Connect takes art for: the size it takes, the
/// simulator screenshot that goes in it, and how the device is drawn around
/// that screenshot. Frame measurements are fractions of the screen's short
/// side, so a frame looks the same at any size.
struct DeviceModel {
    enum Kind {
        /// A phone with a Dynamic Island.
        case phone
        /// A book-style foldable: two halves round a vertical crease.
        case foldable
        case tablet
        case watch
    }

    let id: String
    /// App Store Connect's name for the slot.
    let slot: String
    /// The portrait size App Store Connect takes (landscape swaps it).
    let canvas: CGSize
    /// The App Preview size, portrait.
    let preview: CGSize?
    let kind: Kind
    /// The display's corner radius.
    let screenRadius: CGFloat
    /// The black border round the display.
    let bezel: CGFloat
    /// The metal band outside it.
    let rim: CGFloat
    /// The device's depth, for the tilted hero.
    let depth: CGFloat
    /// A caption's title size, as a fraction of the canvas's short side.
    let titleScale: CGFloat

    static let catalog: [String: DeviceModel] = Dictionary(uniqueKeysWithValues: [
        DeviceModel(id: "iphone-6.3", slot: "iPhone with Dynamic Island (medium display), 6.1\"/6.3\"",
                    canvas: CGSize(width: 1206, height: 2622), preview: CGSize(width: 886, height: 1920),
                    kind: .phone, screenRadius: 0.155, bezel: 0.03, rim: 0.016, depth: 0.105, titleScale: 0.084),
        DeviceModel(id: "iphone-6.9", slot: "iPhone with Dynamic Island (large display), 6.7\"/6.9\"",
                    canvas: CGSize(width: 1320, height: 2868), preview: CGSize(width: 886, height: 1920),
                    kind: .phone, screenRadius: 0.15, bezel: 0.028, rim: 0.015, depth: 0.1, titleScale: 0.084),
        DeviceModel(id: "iphone-duo", slot: "iPhone Duo (inner display)",
                    canvas: CGSize(width: 2007, height: 2853), preview: CGSize(width: 886, height: 1920),
                    kind: .foldable, screenRadius: 0.035, bezel: 0.02, rim: 0.011, depth: 0.04, titleScale: 0.066),
        DeviceModel(id: "iphone-duo-outer", slot: "iPhone Duo (outer display)",
                    canvas: CGSize(width: 1398, height: 2034), preview: CGSize(width: 886, height: 1920),
                    kind: .phone, screenRadius: 0.12, bezel: 0.03, rim: 0.016, depth: 0.15, titleScale: 0.08),
        DeviceModel(id: "ipad-13", slot: "iPad 13\" display",
                    canvas: CGSize(width: 2064, height: 2752), preview: CGSize(width: 1200, height: 1600),
                    kind: .tablet, screenRadius: 0.03, bezel: 0.042, rim: 0.009, depth: 0.025, titleScale: 0.064),
        DeviceModel(id: "watch-46", slot: "Apple Watch Series 10, 11, 12 (46mm)",
                    canvas: CGSize(width: 416, height: 496), preview: nil,
                    kind: .watch, screenRadius: 0.23, bezel: 0.075, rim: 0.075, depth: 0.27, titleScale: 0.08),
        DeviceModel(id: "watch-ultra", slot: "Apple Watch Ultra 3, 4 (49mm)",
                    canvas: CGSize(width: 422, height: 514), preview: nil,
                    kind: .watch, screenRadius: 0.17, bezel: 0.07, rim: 0.1, depth: 0.3, titleScale: 0.08),
    ].map { ($0.id, $0) })

    func canvas(landscape: Bool) -> CGSize {
        landscape ? CGSize(width: canvas.height, height: canvas.width) : canvas
    }
}
