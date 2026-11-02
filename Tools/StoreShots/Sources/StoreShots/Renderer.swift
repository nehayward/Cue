import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum Renderer {
    /// A view drawn at exactly `size` pixels.
    static func image(_ view: some View, size: CGSize) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.cgImage else { throw Failure("SwiftUI drew nothing") }
        return image
    }

    /// A view drawn `size.width` wide and as tall as it needs, up to `size.height`.
    static func image(_ view: some View, size: CGSize, fitting: Bool) throws -> CGImage {
        guard fitting else { return try image(view, size: size) }
        let renderer = ImageRenderer(content: view.frame(width: size.width).fixedSize(horizontal: false, vertical: true))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: size.width, height: nil)
        guard let image = renderer.cgImage else { throw Failure("SwiftUI drew nothing") }
        guard CGFloat(image.height) <= size.height else { throw Failure("a caption is \(image.height) px tall, over \(Int(size.height))") }
        return image
    }

    /// A smooth backdrop drawn at exactly `size` pixels: rendered in 16-bit
    /// floating point, then given the sRGB curve and brought down to 8 bits
    /// with triangular dither under a level strong, so a slow gradient over
    /// a whole canvas neither bands nor shows grain. Plain colours and
    /// linear, radial and elliptical gradients only: SwiftUI linearises a
    /// MeshGradient's colours twice in this mode.
    static func smooth(_ view: some View, size: CGSize) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        renderer.colorMode = .extendedLinear
        guard let image = renderer.cgImage, image.bitsPerComponent == 16, image.bitsPerPixel == 64,
              image.bitmapInfo.contains(.floatComponents), let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { throw Failure("SwiftUI drew no 16-bit backdrop") }
        let width = image.width, height = image.height
        guard let flat = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let target = flat.data else {
            throw Failure("couldn't make a \(width)×\(height) bitmap")
        }
        let sourceRow = image.bytesPerRow / 2, targetRow = flat.bytesPerRow
        let half = UnsafeRawPointer(bytes).assumingMemoryBound(to: Float16.self)
        let narrow = target.bindMemory(to: UInt8.self, capacity: targetRow * height)
        var state: UInt32 = 0x9E37_79B9
        func random() -> Float {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return Float(state >> 8) / Float(1 << 24)
        }
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<3 {
                    let value = max(0, min(1, Float(half[y * sourceRow + x * 4 + channel])))
                    let encoded = value <= 0.003_130_8 ? 12.92 * value : 1.055 * powf(value, 1 / 2.4) - 0.055
                    let dithered = (encoded * 255 + random() - random()).rounded()
                    narrow[y * targetRow + x * 4 + channel] = UInt8(max(0, min(255, dithered)))
                }
            }
        }
        guard let result = flat.makeImage() else { throw Failure("couldn't dither the backdrop") }
        return result
    }

    /// The image on an opaque background with no alpha channel, as App Store
    /// Connect takes it.
    static func opaque(_ image: CGImage, background: CGColor) throws -> CGImage {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw Failure("couldn't make a \(image.width)×\(image.height) bitmap")
        }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(background)
        context.fill(rect)
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        guard let flat = context.makeImage() else { throw Failure("couldn't flatten the image") }
        return flat
    }

    static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure("can't read \(url.path)")
        }
        return image
    }

    static func write(_ image: CGImage, to url: URL, type: UTType = .png) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw Failure("can't write \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure("couldn't save \(url.path)") }
    }

    /// `image` scaled to exactly `size`, filling it (cropping the overflow).
    static func filled(_ image: CGImage, to size: CGSize) throws -> CGImage {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw Failure("couldn't make a \(Int(size.width))×\(Int(size.height)) bitmap")
        }
        let scale = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                       width: drawn.width, height: drawn.height))
        guard let result = context.makeImage() else { throw Failure("couldn't scale the image") }
        return result
    }
}
