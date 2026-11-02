import CoreGraphics
import SwiftUI
import UIKit

/// The iPhone player's background on the watch: a soft gradient built from
/// a 4×4 grid of colours sampled from the cover, interpolated so it reads
/// like a very heavy blur. A copy of `ArtworkMeshBackground`'s (Clic's watch
/// keeps one too, `WatchArtworkMesh`), drawn on the CPU into a small
/// bitmap, as there; keep them in step.
enum WatchArtworkMesh {
    private static let grid = 4
    private static let bitmapSize = 48

    /// The gradient for a cover, from `ArtworkStore`'s copy (fetched if it
    /// isn't here yet), made off the main thread and kept for the next ask.
    @MainActor
    static func gradient(for url: URL) async -> UIImage? {
        let key = url.absoluteString
        if let made = cache[key] { return made }
        guard let cover = await ArtworkStore.shared.fetch(url) else { return nil }
        let rendered = await Task.detached(priority: .utility) {
            WatchArtworkMesh.gradient(for: cover)
        }.value
        if let rendered { store(rendered, for: key) }
        return rendered
    }

    /// One already made, for a view's first frame.
    @MainActor
    static func made(for url: URL?) -> UIImage? {
        url.flatMap { cache[$0.absoluteString] }
    }

    /// The gradient for `image`, nil when its pixels can't be read.
    static func gradient(for image: UIImage) -> UIImage? {
        sampleColors(from: image).flatMap(renderGradient)
    }

    /// The middle of the cover averaged to a `grid`×`grid` set of colours,
    /// saturation ×1.5 (as `ArtworkMeshBackground.sampleColors`).
    private static func sampleColors(from image: UIImage) -> [SIMD3<Float>]? {
        guard let full = image.cgImage else { return nil }
        let inset = 1 - 1 / 1.3
        let crop = CGRect(x: 0, y: 0, width: full.width, height: full.height)
            .insetBy(dx: CGFloat(full.width) * inset / 2, dy: CGFloat(full.height) * inset / 2)
            .integral
        let cgImage = full.cropping(to: crop) ?? full
        var pixels = [UInt8](repeating: 0, count: grid * grid * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: grid, height: grid, bitsPerComponent: 8,
                bytesPerRow: grid * 4, space: CGColorSpaceCreateDeviceRGB(),
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

    /// The colour grid interpolated with Catmull-Rom splines into a
    /// `bitmapSize`² image (as `ArtworkMeshBackground.renderGradient`).
    private static func renderGradient(_ colors: [SIMD3<Float>]) -> UIImage? {
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
                width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // ~9 KB a cover; kept small for the watch.
    @MainActor private static var cache: [String: UIImage] = [:]

    @MainActor private static func store(_ image: UIImage, for key: String) {
        if cache.count >= 20 { cache.removeAll(keepingCapacity: true) }
        cache[key] = image
    }
}
