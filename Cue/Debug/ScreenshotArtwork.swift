#if DEBUG
import Foundation
import Nuke

/// App Store screenshots with every cover blurred, since the albums, books
/// and stations on a test server aren't Cue's to show: launch a Debug build
/// with `-dance.cue.blurArtwork YES`. Every cover is decoded through Nuke's
/// shared pipeline, so this wraps the decoder the registry picks for each
/// request (keeping its thumbnail options) and blurs what it returns.
enum ScreenshotArtwork {
    static var blurs: Bool {
        UserDefaults.standard.bool(forKey: "dance.cue.blurArtwork")
    }

    static func decoder(for context: ImageDecodingContext) -> (any ImageDecoding)? {
        ImageDecoderRegistry.shared.decoder(for: context).map(BlurringDecoder.init)
    }
}

private struct BlurringDecoder: ImageDecoding {
    let base: any ImageDecoding

    func decode(_ data: Data) throws -> ImageContainer {
        var container = try base.decode(data)
        let image = container.image
        // A fifteenth of the longer side: as blurred in a 60 pt row as on the
        // player, whatever size the cover was decoded at.
        let side = max(image.size.width, image.size.height) * image.scale
        if let blurred = ImageProcessors.GaussianBlur(radius: max(4, Int(side / 15))).process(image) {
            container.image = blurred
        }
        return container
    }
}
#endif
