import CoreImage
import CoreImage.CIFilterBuiltins
import Nuke
import UIKit

/// Blurs the foot of an image more and more towards its bottom edge, the way
/// a page's header lets its cover melt into the page: sharp down to `start`
/// (a fraction of the height from the top), at `radius` (a fraction of the
/// height) at the bottom, with `grain` (Glur's noise) over the blur. Core
/// Image's `CIMaskedVariableBlur` under a gradient mask, run once when the
/// image loads and kept in Nuke's cache with it, so nothing is drawn per
/// frame (see Mac GPU cost in CLAUDE.md).
struct ProgressiveBlur: ImageProcessing, Hashable {
    var start: CGFloat = 0.55
    var radius: CGFloat = 0.045
    var grain: CGFloat = 0.15

    var identifier: String {
        "dance.cue/progressive-blur?start=\(start)&radius=\(radius)&grain=\(grain)&ease=smooth&opaque"
    }

    func process(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        let extent = input.extent

        // Core Image's y runs up from the bottom: white (full blur) at the
        // foot, black (sharp) where the blur begins. Smoothstepped
        // (3t² − 2t³), so the blur creeps in under the start instead of
        // beginning at a line a fine texture shows, and evens out at the
        // foot. A polynomial, not CIToneCurve, which bends the ramp in
        // sRGB and made it jump.
        let ramp = CIFilter.linearGradient()
        ramp.point0 = CGPoint(x: 0, y: extent.height * (1 - start))
        ramp.color0 = CIColor.black
        ramp.point1 = CGPoint(x: 0, y: 0)
        ramp.color1 = CIColor.white
        let ease = CIFilter.colorPolynomial()
        ease.inputImage = ramp.outputImage?.cropped(to: extent)
        let smoothstep = CIVector(x: 0, y: 0, z: 3, w: -2)
        ease.redCoefficients = smoothstep
        ease.greenCoefficients = smoothstep
        ease.blueCoefficients = smoothstep
        ease.alphaCoefficients = CIVector(x: 0, y: 1, z: 0, w: 0)
        let mask = ease.outputImage

        let blur = CIFilter.maskedVariableBlur()
        // Clamped so the edges blur into themselves, not fade to clear.
        blur.inputImage = input.clampedToExtent()
        blur.mask = mask
        blur.radius = Float(extent.height * radius)

        // Grain where it's blurred: a blur this smooth bands in 8 bits, and
        // a little noise hides it. Grey noise around mid-grey, overlaid, so
        // it textures the blur without lightening or darkening it. Its alpha
        // is random too, so it's set to 1 first: unpremultiplied, a pixel
        // of tiny alpha comes out thousands of times too bright.
        let noise = CIFilter.randomGenerator().outputImage?
            .cropped(to: extent)
            .settingAlphaOne(in: extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: grain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: grain, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: grain, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0.5 - grain / 2, y: 0.5 - grain / 2, z: 0.5 - grain / 2, w: 1)
            ])
            .cropped(to: extent)
        let grained = CIFilter.overlayBlendMode()
        grained.inputImage = noise
        grained.backgroundImage = blur.outputImage?.cropped(to: extent)
        let grainy = CIFilter.blendWithMask()
        grainy.inputImage = grained.outputImage
        grainy.backgroundImage = blur.outputImage?.cropped(to: extent)
        grainy.maskImage = mask

        // BGRA, the layout Core Animation draws, so it needn't keep a copy,
        // in the cover's own colours when they're RGB (P3 stays P3); a
        // grayscale cover, which BGRA can't hold, comes out in sRGB. With
        // no alpha when the cover has none (nearly every one): Nuke's disk
        // cache encodes anything with an alpha channel as a PNG, and a
        // grained 800 px PNG is several times the JPEG it keeps otherwise.
        let colorSpace = cgImage.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let output = grainy.outputImage?.cropped(to: extent),
              let blurred = (cgImage.hasAlpha ? nil : Self.opaqueImage(output, colorSpace: colorSpace))
                ?? Self.context.createCGImage(output, from: extent, format: .BGRA8, colorSpace: colorSpace) else {
            return nil
        }
        return UIImage(cgImage: blurred, scale: image.scale, orientation: image.imageOrientation)
    }

    /// `image` rendered into a BGRA bitmap whose alpha byte is skipped,
    /// which Nuke stores as a JPEG. Nil when Core Graphics can't draw in
    /// the cover's colour space; the caller then keeps the alpha.
    private static func opaqueImage(_ image: CIImage, colorSpace: CGColorSpace) -> CGImage? {
        let extent = image.extent
        guard let bitmap = CGContext(
            data: nil,
            width: Int(extent.width),
            height: Int(extent.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ), let pixels = bitmap.data else {
            return nil
        }
        Self.context.render(image, toBitmap: pixels, rowBytes: bitmap.bytesPerRow, bounds: extent, format: .BGRA8, colorSpace: colorSpace)
        return bitmap.makeImage()
    }

    /// Its own context rather than Nuke's shared one, which keeps every
    /// intermediate it renders: none kept between covers. Not an 8-bit
    /// working format: on iOS it leaves the masked blur's sharp part black.
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .priorityRequestLow: true
    ])
}

private extension CGImage {
    /// Whether it has an alpha channel, the test Nuke's encoder makes
    /// between PNG and JPEG.
    var hasAlpha: Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }
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
