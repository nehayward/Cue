import CoreImage
import CoreImage.CIFilterBuiltins
import Nuke
import UIKit

/// Blurs the foot of an image more and more towards its bottom edge, the way
/// a page's header lets its cover melt into the page: sharp down to `start`
/// (a fraction of the height from the top), at `radius` (a fraction of the
/// height) at the bottom. Core Image's `CIMaskedVariableBlur` under a
/// gradient mask, run once when the image loads and kept in Nuke's cache
/// with it, so nothing is drawn per frame (see Mac GPU cost in CLAUDE.md).
struct ProgressiveBlur: ImageProcessing, Hashable {
    var start: CGFloat = 0.6
    var radius: CGFloat = 0.045

    var identifier: String {
        "dance.cue/progressive-blur?start=\(start)&radius=\(radius)"
    }

    func process(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        let extent = input.extent

        // Core Image's y runs up from the bottom: white (full blur) at the
        // foot, black (sharp) where the blur begins.
        let mask = CIFilter.linearGradient()
        mask.point0 = CGPoint(x: 0, y: extent.height * (1 - start))
        mask.color0 = CIColor.black
        mask.point1 = CGPoint(x: 0, y: 0)
        mask.color1 = CIColor.white

        let blur = CIFilter.maskedVariableBlur()
        // Clamped so the edges blur into themselves, not fade to clear.
        blur.inputImage = input.clampedToExtent()
        blur.mask = mask.outputImage?.cropped(to: extent)
        blur.radius = Float(extent.height * radius)

        // BGRA, the layout Core Animation draws, so it needn't keep a copy,
        // in the cover's own colours when they're RGB (P3 stays P3); a
        // grayscale cover, which BGRA can't hold, comes out in sRGB.
        let colorSpace = cgImage.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let output = blur.outputImage?.cropped(to: extent),
              let blurred = Self.context.createCGImage(output, from: extent, format: .BGRA8, colorSpace: colorSpace) else {
            return nil
        }
        return UIImage(cgImage: blurred, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Its own context rather than Nuke's shared one, which keeps every
    /// intermediate it renders: none kept between covers. Not an 8-bit
    /// working format: on iOS it leaves the masked blur's sharp part black.
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .priorityRequestLow: true
    ])
}

extension ImageRequest {
    /// This request with its image's foot blurred (`ProgressiveBlur`), as a
    /// page's header draws its cover.
    var withBlurredFoot: ImageRequest {
        var request = self
        request.processors.append(ProgressiveBlur())
        return request
    }
}
