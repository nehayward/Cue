#if DEBUG
import CoreGraphics
import UIKit

/// App Store screenshots of the watch with every cover blurred, as on the
/// iPhone (`ScreenshotArtwork`): launch a Debug build with
/// `-dance.cue.blurArtwork YES`. watchOS has no Core Image, and Core Graphics
/// there scales up without smoothing, so the cover is drawn small and
/// box-blurred by hand, three passes each way, about a Gaussian.
enum WatchScreenshotArtwork {
    static var blurs: Bool {
        UserDefaults.standard.bool(forKey: "dance.cue.blurArtwork")
    }

    /// The cover as it goes on screen: blurred while `blurs` is on.
    static func prepared(_ image: UIImage) -> UIImage {
        let side = 96
        guard blurs, let cover = image.cgImage,
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return image }
        context.interpolationQuality = .high
        context.draw(cover, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        for _ in 0..<3 {
            boxBlur(pixels, side: side, radius: side / 12, horizontal: true)
            boxBlur(pixels, side: side, radius: side / 12, horizontal: false)
        }
        return context.makeImage().map { UIImage(cgImage: $0) } ?? image
    }

    /// One pass of a running-sum box blur along rows or columns, edges held.
    private static func boxBlur(_ pixels: UnsafeMutablePointer<UInt8>, side: Int, radius: Int, horizontal: Bool) {
        var line = [Int](repeating: 0, count: side * 4)
        let width = 2 * radius + 1
        for outer in 0..<side {
            func index(_ inner: Int) -> Int {
                let clamped = min(side - 1, max(0, inner))
                return (horizontal ? outer * side + clamped : clamped * side + outer) * 4
            }
            for channel in 0..<4 {
                var sum = 0
                for inner in -radius...radius { sum += Int(pixels[index(inner) + channel]) }
                for inner in 0..<side {
                    line[inner * 4 + channel] = sum / width
                    sum += Int(pixels[index(inner + radius + 1) + channel]) - Int(pixels[index(inner - radius) + channel])
                }
            }
            for inner in 0..<side {
                let target = index(inner)
                for channel in 0..<4 { pixels[target + channel] = UInt8(line[inner * 4 + channel]) }
            }
        }
    }
}
#endif
