import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// An App Preview: the app's own screen recordings, each under a caption,
/// laid along one long strip of the set's backdrop. The camera holds on a
/// scene while its recording plays, then pans to the next, the backdrop a
/// little slower than the screens for depth. The first screen can swing in
/// from a tilt. Written as H.264 at 30 fps with a silent stereo AAC track,
/// as App Store Connect asks.
enum PreviewRenderer {
    static func renderAll(_ workspace: Workspace, names: [String]) throws {
        let previews = (workspace.project.previews ?? []).filter { names.isEmpty || names.contains($0.name) }
        guard !previews.isEmpty else { throw Failure("no previews in the project") }
        for spec in previews {
            try render(spec, in: workspace)
        }
    }

    static func render(_ spec: PreviewSpec, in workspace: Workspace) throws {
        let project = workspace.project
        let model = try workspace.model(spec.device)
        guard let defaultSize = spec.size.map({ CGSize(width: $0[0], height: $0[1]) }) ?? model.preview else {
            throw Failure("\(spec.name): \(model.id) takes no previews; give it a size")
        }
        let size = defaultSize
        let fps = spec.fps ?? 30
        let transition = spec.transition ?? 0.55
        let scenes = try spec.scenes.map { try SceneSource($0, device: spec.device, workspace: workspace) }
        guard let first = scenes.first else { throw Failure("\(spec.name) has no scenes") }

        // Layout, the same for every scene so the screen never jumps: the
        // captions share a band as tall as the tallest, the screen fills
        // what's left, its aspect the recordings'.
        let short = min(size.width, size.height)
        let margin = short * 0.07
        let titleSize = short * 0.084
        let captions = try spec.scenes.map { scene in
            try Renderer.image(
                Caption(title: scene.title, subtitle: scene.subtitle, theme: project.theme, titleSize: titleSize,
                        width: size.width - 2 * margin)
                    .frame(width: size.width - 2 * margin)
                    .padding(.vertical, titleSize * 0.4),
                size: CGSize(width: size.width - 2 * margin, height: size.height * 0.3), fitting: true)
        }
        let band = CGFloat(captions.map(\.height).max() ?? 0)
        let top = size.height * 0.035
        let bottom = size.height * 0.04
        let aspect = first.aspect
        let available = CGSize(width: size.width * 0.82, height: size.height - top - band - bottom - size.height * 0.015)
        // Core Image's origin is the bottom left.
        let layout: Layout
        var phone: Phone3D?
        if spec.frame == true {
            // The screen inside the device in 3D: the device fills what's
            // left, rendered on a canvas with room round it to turn.
            let border = 2 * (model.bezel + model.rim) * min(1, aspect)
            let width = min(available.width / (1 + border), available.height / (aspect + border)).rounded()
            let screenSize = CGSize(width: width, height: (width * aspect).rounded())
            let device = CGSize(width: width * (1 + border), height: width * (aspect + border))
            let canvas = CGSize(width: (device.width * 1.36).rounded(), height: (device.height * 1.14).rounded())
            let floor = (project.theme.palette.first ?? project.theme.base).cgColor
            phone = Phone3D(model: model, screenSize: screenSize, canvas: canvas, finish: project.theme.finish, floor: floor)
            layout = Layout(size: size,
                            box: CGRect(x: ((size.width - canvas.width) / 2).rounded(),
                                        y: (bottom - (canvas.height - device.height) / 2).rounded(),
                                        width: canvas.width, height: canvas.height),
                            screen: screenSize, radius: width * model.screenRadius, captionTop: size.height - top)
        } else {
            let width = min(available.width, available.height / aspect).rounded()
            let screenSize = CGSize(width: width, height: (width * aspect).rounded())
            layout = Layout(size: size,
                            box: CGRect(origin: CGPoint(x: ((size.width - screenSize.width) / 2).rounded(), y: bottom), size: screenSize),
                            screen: screenSize, radius: width * model.screenRadius, captionTop: size.height - top)
        }

        // The backdrop: one strip as wide as every scene side by side.
        let strip = try Renderer.smooth(
            HStack(spacing: 0) {
                ForEach(0..<scenes.count, id: \.self) { index in
                    Backdrop(theme: project.theme, index: index).frame(width: size.width, height: size.height)
                }
            },
            size: CGSize(width: size.width * CGFloat(scenes.count), height: size.height))
        let pieces = Pieces(layout: layout, strip: CIImage(cgImage: strip), captions: captions.map { CIImage(cgImage: $0) },
                            phone: phone)

        let url = workspace.outputFolder.appendingPathComponent("previews").appendingPathComponent(spec.name + ".mp4")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        let starts = scenes.indices.map { index in scenes[..<index].reduce(0) { $0 + $1.duration } }
        let total = scenes.reduce(0) { $0 + $1.duration }
        let writer = try MovieWriter(url: url, size: size, fps: fps, duration: total)
        let frameCount = Int((total * Double(fps)).rounded())
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
        var stills: [(Double, CGImage)] = []
        print("\(spec.name): \(Int(size.width))×\(Int(size.height)), \(String(format: "%.1f", total)) s, \(scenes.count) scenes")

        for frame in 0..<frameCount {
            let time = Double(frame) / Double(fps)
            // Where the camera is along the strip, in scenes: whole numbers
            // while a scene holds, easing between them across each cut.
            var position = 0.0
            for index in 1..<max(1, scenes.count) {
                let cut = starts[index]
                let progress = (time - (cut - transition / 2)) / transition
                position += ease(min(1, max(0, progress)))
            }
            var image = pieces.backdrop(at: position * 0.65)
            // The scenes on screen now: the one at the camera and its neighbour mid-pan.
            for index in Set([Int(position.rounded(.down)), Int(position.rounded(.up))]) where scenes.indices.contains(index) {
                let offset = (Double(index) - position) * size.width
                let sceneTime = time - starts[index]
                let screen = try scenes[index].frame(at: sceneTime)
                let swing = index == 0 && (spec.tiltIn ?? true) ? max(0, 1 - ease(min(1, time / 1.1))) : 0
                // A slow sway, so a held scene still feels alive.
                let sway = spec.float == true ? sin(2 * .pi * time / 7) : 0
                if pieces.phone != nil {
                    guard let pixels = context.createCGImage(screen, from: screen.extent) else {
                        throw Failure("couldn't read a frame of scene \(index + 1)")
                    }
                    let nod = spec.float == true ? sin(2 * .pi * time / 9 + 1) : 0
                    image = try pieces.phone(pixels, offset: offset, yaw: -0.55 * swing + 0.13 * sway,
                                             pitch: 0.16 * swing + 0.035 * nod).composited(over: image)
                } else {
                    image = pieces.screen(screen, offset: offset, swing: swing + 0.1 * sway).composited(over: image)
                }
                image = pieces.caption(index, offset: offset * 1.15, fade: 1 - min(1, abs(Double(index) - position) * 1.6))
                    .composited(over: image)
            }
            try writer.append(image, at: frame, context: context)
            if frame % (fps * 2) == fps {
                if let still = context.createCGImage(image, from: CGRect(origin: .zero, size: size)) {
                    stills.append((time, still))
                }
            }
        }
        try writer.finish()
        print("\(spec.name): \(url.path)")
        try writeStrip(stills, size: size, to: url.deletingPathExtension().appendingPathExtension("frames.png"))
    }

    private static func ease(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    /// Frames every two seconds side by side, small, to look the movie over.
    private static func writeStrip(_ stills: [(Double, CGImage)], size: CGSize, to url: URL) throws {
        guard !stills.isEmpty else { return }
        let height: CGFloat = 640
        let width = size.width * height / size.height
        let view = HStack(spacing: 16) {
            ForEach(Array(stills.enumerated()), id: \.offset) { _, still in
                VStack(spacing: 6) {
                    Image(decorative: still.1, scale: 1).resizable().frame(width: width, height: height)
                    Text(String(format: "%.0f s", still.0)).font(.system(size: 22, weight: .semibold, design: .rounded))
                }
            }
        }
        .padding(16)
        .background(.white)
        let image = try Renderer.image(view, size: CGSize(width: (width + 16) * CGFloat(stills.count) + 16, height: height + 70))
        try Renderer.write(try Renderer.opaque(image, background: .white), to: url)
        print("frames: \(url.path)")
    }

    struct Layout {
        let size: CGSize
        /// What's placed on the canvas: the screen, or the device round it.
        let box: CGRect
        let screen: CGSize
        let radius: CGFloat
        /// The caption band's top edge, from the bottom.
        let captionTop: CGFloat
    }

    /// What each frame is put together from, made once.
    struct Pieces {
        let layout: Layout
        let strip: CIImage
        let captions: [CIImage]
        /// The device in 3D round the recording, for framed previews.
        let phone: Phone3D?
        let mask: CIImage
        let shadow: CIImage

        init(layout: Layout, strip: CIImage, captions: [CIImage], phone: Phone3D?) {
            self.layout = layout
            self.strip = strip
            self.captions = captions
            self.phone = phone
            let rect = CGRect(origin: .zero, size: layout.screen)
            let path = CGPath(roundedRect: rect, cornerWidth: layout.radius, cornerHeight: layout.radius, transform: nil)
            let context = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height), bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.addPath(path)
            context.setFillColor(.white)
            context.fillPath()
            mask = CIImage(cgImage: context.makeImage()!)
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = mask.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.5),
            ])
            blur.radius = Float(layout.size.width * 0.035)
            shadow = blur.outputImage!.transformed(by: CGAffineTransform(translationX: 0, y: -layout.size.width * 0.02))
        }

        func backdrop(at position: Double) -> CIImage {
            strip.transformed(by: CGAffineTransform(translationX: -position * layout.size.width, y: 0))
                .cropped(to: CGRect(origin: .zero, size: layout.size))
        }

        /// The screen, rounded, on its shadow; `swing` from 1 (turned away) to
        /// 0 (flat) for the opening.
        func screen(_ image: CIImage, offset: Double, swing: Double) -> CIImage {
            let size = layout.screen
            let scaled = image.transformed(by: CGAffineTransform(scaleX: size.width / image.extent.width,
                                                                 y: size.height / image.extent.height))
            let rounded = scaled.applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
            ])
            var layer = rounded.composited(over: shadow)
            if swing != 0 {
                layer = turned(layer, size: layout.box.size, amount: swing)
            }
            return layer.transformed(by: CGAffineTransform(translationX: layout.box.minX + offset, y: layout.box.minY))
        }

        /// The device in 3D with `frame` on its screen, turned by `yaw` and
        /// `pitch` (radians).
        func phone(_ frame: CGImage, offset: Double, yaw: Double, pitch: Double) throws -> CIImage {
            guard let phone else { return .empty() }
            return try phone.render(frame, yaw: yaw, pitch: pitch)
                .transformed(by: CGAffineTransform(translationX: layout.box.minX + offset, y: layout.box.minY))
        }

        /// The layer turned about its vertical axis and drawn back, in perspective.
        private func turned(_ layer: CIImage, size: CGSize, amount: Double) -> CIImage {
            let yaw = -0.62 * amount, pitch = 0.18 * amount
            let distance = size.height * 2.4
            let lift = size.height * 0.03 * amount
            func project(_ x: Double, _ y: Double) -> CGPoint {
                // Centred, turned about y then x, pushed back, projected.
                let cx = x - size.width / 2, cy = y - size.height / 2
                let x1 = cx * cos(yaw), z1 = -cx * sin(yaw)
                let y2 = cy * cos(pitch) - z1 * sin(pitch), z2 = cy * sin(pitch) + z1 * cos(pitch)
                let scale = distance / (distance - z2 + size.height * 0.25 * amount)
                return CGPoint(x: x1 * scale + size.width / 2, y: y2 * scale + size.height / 2 + lift)
            }
            // The filter moves the image's extent corners, so give it a set
            // extent (the shadow round the box) and move those corners.
            let margin = size.width * 0.15
            let extent = CGRect(origin: .zero, size: size).insetBy(dx: -margin, dy: -margin)
            let filter = CIFilter.perspectiveTransform()
            filter.inputImage = layer.cropped(to: extent)
            filter.topLeft = project(extent.minX, extent.maxY)
            filter.topRight = project(extent.maxX, extent.maxY)
            filter.bottomRight = project(extent.maxX, extent.minY)
            filter.bottomLeft = project(extent.minX, extent.minY)
            return filter.outputImage ?? layer
        }

        func caption(_ index: Int, offset: Double, fade: Double) -> CIImage {
            guard captions.indices.contains(index), fade > 0 else { return .empty() }
            let caption = captions[index]
            let x = (layout.size.width - caption.extent.width) / 2 + offset
            let y = layout.captionTop - caption.extent.height
            return caption
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: fade)])
                .transformed(by: CGAffineTransform(translationX: x, y: y))
        }
    }
}

/// One scene's pictures: a recording read in order, or a still.
final class SceneSource {
    let duration: Double
    let aspect: CGFloat
    private let from: Double
    private let rate: Double
    private let still: CIImage?
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var current: CIImage?
    private var upcoming: (time: Double, image: CIImage)?
    private let url: URL?

    init(_ scene: PreviewScene, device: String, workspace: Workspace) throws {
        duration = scene.duration
        from = scene.from ?? 0
        rate = scene.rate ?? 1
        if let clip = scene.clip {
            let url = workspace.clipsFolder.appendingPathComponent(device).appendingPathComponent(clip + ".mov")
            guard FileManager.default.fileExists(atPath: url.path) else { throw Failure("no recording \(url.path)") }
            self.url = url
            still = nil
            let asset = AVURLAsset(url: url)
            guard let track = asset.tracks(withMediaType: .video).first else { throw Failure("\(url.path) has no video") }
            aspect = track.naturalSize.height / track.naturalSize.width
        } else if let name = scene.still {
            let image = try Renderer.load(workspace.raw(device, name))
            still = CIImage(cgImage: image)
            aspect = CGFloat(image.height) / CGFloat(image.width)
            url = nil
        } else {
            throw Failure("a scene needs a clip or a still")
        }
    }

    /// The picture `time` seconds into the scene (before zero it holds the first).
    func frame(at time: Double) throws -> CIImage {
        if let still { return still }
        let clipTime = from + max(0, time) * rate
        if reader == nil { try open() }
        // Read on until the next frame is later than the time asked for.
        while true {
            if upcoming == nil, let output, let sample = output.copyNextSampleBuffer(),
               let buffer = CMSampleBufferGetImageBuffer(sample) {
                upcoming = (CMSampleBufferGetPresentationTimeStamp(sample).seconds, CIImage(cvPixelBuffer: buffer))
            }
            guard let next = upcoming, next.time <= clipTime || current == nil else { break }
            current = next.image
            upcoming = nil
        }
        guard let current else { throw Failure("\(url?.lastPathComponent ?? "a recording") has no frames at \(clipTime) s") }
        return current
    }

    private func open() throws {
        guard let url else { return }
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { throw Failure("\(url.path) has no video") }
        let reader = try AVAssetReader(asset: asset)
        // Start a little early: a recording only has frames when the screen
        // changed, so the picture showing at `from` may be from before it.
        let start = max(0, from - 3)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: .positiveInfinity)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw Failure("can't read \(url.path): \(String(describing: reader.error))") }
        self.reader = reader
        self.output = output
    }
}

/// H.264 video and a silent stereo AAC track, interleaved.
final class MovieWriter {
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let size: CGSize
    private let fps: Int
    private let duration: Double
    private var audioFrames: Int64 = 0
    private var audioFinished = false
    private let sampleRate = 48_000.0
    private let audioFormat: CMAudioFormatDescription

    init(url: URL, size: CGSize, fps: Int, duration: Double) throws {
        self.size = size
        self.fps = fps
        self.duration = duration
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 11_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264High40,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        video.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16,
            mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard let format else { throw Failure("couldn't describe the audio") }
        audioFormat = format
        audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 256_000,
        ], sourceFormatHint: format)
        audio.expectsMediaDataInRealTime = false
        writer.add(video)
        writer.add(audio)
        guard writer.startWriting() else { throw Failure("can't write \(url.path): \(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: CIImage, at frame: Int, context: CIContext) throws {
        let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
        // The writer interleaves, and holds the video back until the audio
        // is a little ahead of it.
        try appendSilence(until: min(duration, time.seconds + 1))
        try wait(for: video)
        guard let pool = adaptor.pixelBufferPool else { throw Failure("no pixel buffers: \(String(describing: writer.error))") }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw Failure("no pixel buffer") }
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        context.render(image, to: buffer, bounds: CGRect(origin: .zero, size: size),
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw Failure("couldn't add frame \(frame): \(String(describing: writer.error))")
        }
    }

    func finish() throws {
        try appendSilence(until: duration)
        video.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 600))
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw Failure("the movie didn't finish: \(String(describing: writer.error))") }
    }

    private func appendSilence(until seconds: Double) throws {
        let target = Int64(seconds * sampleRate)
        while audioFrames < target {
            let count = Int(min(1024, target - audioFrames))
            try wait(for: audio)
            let bytes = count * 4
            var block: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                               customBlockSource: nil, offsetToData: 0, dataLength: bytes,
                                               flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
            guard let block else { throw Failure("no audio buffer") }
            CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: audioFormat, sampleCount: count,
                presentationTimeStamp: CMTime(value: audioFrames, timescale: CMTimeScale(sampleRate)),
                packetDescriptions: nil, sampleBufferOut: &sample)
            guard let sample, audio.append(sample) else {
                throw Failure("couldn't add audio: \(String(describing: writer.error))")
            }
            audioFrames += Int64(count)
        }
        // Done: the writer would otherwise hold the video back for more.
        if !audioFinished, audioFrames >= Int64(duration * sampleRate) {
            audio.markAsFinished()
            audioFinished = true
        }
    }

    private func wait(for input: AVAssetWriterInput) throws {
        var waited = 0
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing else { throw Failure("writer stopped: \(String(describing: writer.error))") }
            Thread.sleep(forTimeInterval: 0.002)
            waited += 1
            if waited > 5_000 { throw Failure("the writer stalled on \(input.mediaType.rawValue) at \(String(format: "%.2f", Double(audioFrames) / sampleRate)) s of audio") }
        }
    }
}
