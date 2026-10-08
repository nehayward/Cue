import Nuke
import SwiftUI
import SonosKit
import MusicSearchKit

/// The player background: a soft gradient built from a 4×4 grid of colours
/// sampled from the cover. The grid keeps the cover's layout (a light sky
/// stays at the top) and is interpolated smoothly, so it reads like a very
/// heavy blur with no stretched-pixel creases.
///
/// The gradient is computed once on the CPU into a small bitmap and drawn as a
/// plain image. It replaces a live `.blur(radius: 80)` over the full-size cover,
/// which rendered and blurred a window-sized offscreen buffer on every frame
/// of a crossfade (often 5000+ px wide on the Mac). A SwiftUI `MeshGradient`
/// looked the same but is re-rendered on the GPU whenever its colours change:
/// on the Mac every room switch cost a fixed ~90 MB of GPU memory for ~2 s.
/// Track changes crossfade the bitmaps.
///
/// Used by both players: a speaker group's (`init(group:)`) and this device's
/// (`init(content:)`).
struct ArtworkMeshBackground: View {
    /// Whose player this is: a room's coordinator, or this device. A switch
    /// swaps the gradient without animating — two players' covers have no
    /// continuity — matching `ArtworkView`.
    let sourceID: String
    let artworkURL: URL?
    /// Names the cover: one gradient per key.
    let artworkKey: String
    /// Nothing is playing, so there's no track change in flight to hold the
    /// old gradient through.
    let isEmpty: Bool

    @State private var image: UIImage?
    @State private var imageKey: String?
    /// The player `image` was made for.
    @State private var imageSourceID: String?
    /// When the gradient last changed, so skips in quick succession swap it
    /// rather than stacking one 0.8 s crossfade on another — each a
    /// full-screen layer kept alive under the blur until it finishes.
    @State private var lastChange: Date = .distantPast

    nonisolated private static let grid = 4
    /// Output size in pixels. The interpolated field is smooth, so a small
    /// bitmap scaled up with high-quality filtering looks the same as a
    /// full-resolution one.
    nonisolated private static let bitmapSize = 48

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .id(imageKey)
                    .transition(.opacity)
            }
        }
        .task(id: "\(sourceID)|\(artworkKey)|\(artworkURL?.absoluteString ?? "")") {
            await load()
        }
    }

    private func load() async {
        let isSourceSwitch = imageSourceID != sourceID
        guard let url = artworkURL else {
            // Hold the outgoing image while a track change is in flight
            // (Sonos reports the new item before its art), as ArtworkView does.
            if isEmpty || isSourceSwitch { set(nil, key: nil, animated: false) }
            return
        }
        let key = artworkKey
        if let cached = Self.cache[key] {
            set(cached, key: key, animated: !isSourceSwitch)
            return
        }
        var request = ImageRequest(url: url, priority: .high)
        request.imageID = key
        request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 32)
        guard let cover = try? await ImagePipeline.shared.image(for: request) else { return }
        // Sampled and drawn off the main thread, which a song change keeps
        // busy enough already.
        let rendered = await Task.detached(priority: .userInitiated) {
            Self.sampleColors(from: cover).flatMap(Self.renderGradient)
        }.value
        guard let gradient = rendered, !Task.isCancelled else { return }
        Self.store(gradient, for: key)
        set(gradient, key: key, animated: !isSourceSwitch)
    }

    private func set(_ new: UIImage?, key: String?, animated: Bool) {
        imageSourceID = sourceID
        guard key != imageKey else { return }
        let now = Date.now
        let isQuickSkip = now.timeIntervalSince(lastChange) < 1
        lastChange = now
        if animated, !isQuickSkip {
            withAnimation(.smooth(duration: 0.8)) {
                image = new
                imageKey = key
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                image = new
                imageKey = key
            }
        }
    }

    /// Averages the middle of the cover down to a `grid`×`grid` set of RGB
    /// colours, top row first. The middle because the blurred background this
    /// replaced was zoomed 1.3× and aspect-filled, so the cover's edges (often
    /// a plain sky or border) never set its colour. Averaging also mutes
    /// colour, hence saturation ×1.5 rather than that background's 1.3.
    nonisolated static func sampleColors(from image: UIImage) -> [SIMD3<Float>]? {
        guard let full = image.cgImage else { return nil }
        let inset = 1 - 1 / 1.3
        let crop = CGRect(x: 0, y: 0, width: full.width, height: full.height)
            .insetBy(dx: CGFloat(full.width) * inset / 2, dy: CGFloat(full.height) * inset / 2)
            .integral
        let cgImage = full.cropping(to: crop) ?? full
        var pixels = [UInt8](repeating: 0, count: grid * grid * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: grid,
                height: grid,
                bitsPerComponent: 8,
                bytesPerRow: grid * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: grid, height: grid))
            return true
        }
        guard drawn else { return nil }
        return (0..<(grid * grid)).map { index in
            let sampled = UIColor(
                red: CGFloat(pixels[index * 4]) / 255,
                green: CGFloat(pixels[index * 4 + 1]) / 255,
                blue: CGFloat(pixels[index * 4 + 2]) / 255,
                alpha: 1
            )
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            sampled.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            let boosted = UIColor(hue: hue, saturation: min(1, saturation * 1.5), brightness: brightness, alpha: 1)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
            boosted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return SIMD3(Float(red), Float(green), Float(blue))
        }
    }

    /// Interpolates the colour grid into a `bitmapSize`² image with
    /// Catmull-Rom splines, which pass through every sampled colour and stay
    /// smooth across grid lines (bilinear leaves visible creases).
    nonisolated static func renderGradient(_ colors: [SIMD3<Float>]) -> UIImage? {
        guard colors.count == grid * grid else { return nil }
        let size = bitmapSize
        func color(_ column: Int, _ row: Int) -> SIMD3<Float> {
            colors[min(max(row, 0), grid - 1) * grid + min(max(column, 0), grid - 1)]
        }
        func catmullRom(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
            let a = 2 * p1
            let b = p2 - p0
            let c = 2 * p0 - 5 * p1 + 4 * p2 - p3
            let d = 3 * p1 - p0 - 3 * p2 + p3
            return 0.5 * (a + b * t + c * t * t + d * t * t * t)
        }
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        let scale = Float(grid - 1) / Float(size - 1)
        for y in 0..<size {
            let gy = Float(y) * scale
            let row = min(Int(gy), grid - 2)
            let ty = gy - Float(row)
            for x in 0..<size {
                let gx = Float(x) * scale
                let column = min(Int(gx), grid - 2)
                let tx = gx - Float(column)
                // Interpolate four rows horizontally, then the results vertically.
                let rows = (-1...2).map { offset in
                    catmullRom(color(column - 1, row + offset), color(column, row + offset),
                               color(column + 1, row + offset), color(column + 2, row + offset), tx)
                }
                let value = catmullRom(rows[0], rows[1], rows[2], rows[3], ty).clamped(lowerBound: .zero, upperBound: .one)
                let index = (y * size + x) * 4
                pixels[index] = UInt8(value.x * 255)
                pixels[index + 1] = UInt8(value.y * 255)
                pixels[index + 2] = UInt8(value.z * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: size,
                height: size,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // ~9 KB per cover; capped so a long session doesn't grow it.
    private static var cache: [String: UIImage] = [:]

    private static func store(_ image: UIImage, for key: String) {
        if cache.count >= 200 { cache.removeAll(keepingCapacity: true) }
        cache[key] = image
    }
}

extension ArtworkMeshBackground {
    /// A speaker group's player.
    init(group: GroupRoom) {
        let track = group.coordinatorRoom.track
        self.init(
            sourceID: group.coordinatorID,
            artworkURL: track.artworkURL,
            artworkKey: track.playerArtworkCacheKey,
            isEmpty: track.isEmpty
        )
    }

    /// This device's player. Named the way the player's own
    /// `ContentArtworkView` names the cover (full-size artwork when there is
    /// one, `#full` on the key), so the download it already made is reused.
    init(content: PlayableContent?) {
        let fullSize = content?.artwork
        let key = content.map { fullSize == nil ? $0.imageKey : "\($0.imageKey)#full" } ?? ""
        self.init(
            sourceID: Self.deviceSourceID,
            artworkURL: fullSize ?? content?.thumbnail,
            artworkKey: key,
            isEmpty: content == nil
        )
    }

    private static let deviceSourceID = "this-device"
}
