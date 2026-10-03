import Defaults
import Nuke
import UIKit

extension ImageRequest.UserInfoKey {
    /// A request Screenshot Artwork leaves alone: the player background
    /// (`ArtworkMeshBackground`) samples the real cover, so the gradient it
    /// paints is the same one the cover on top of it turns into.
    static let realCover: ImageRequest.UserInfoKey = "dance.cue.realCover"
}

#if DEBUG
/// App Store screenshots can't show other people's album covers, so Screenshot
/// Artwork draws every cover as the gradient the player paints behind it
/// (`ArtworkMeshBackground`): the cover's own colours and layout, nothing
/// recognisable. It works in the image pipeline, so lists, grids, the player,
/// the Lock Screen card and CarPlay all change together.
///
/// Debug builds only. Turned on in Settings ▸ Debug ▸ Screenshot Artwork, by
/// the `-ScreenshotArtwork` launch argument, or by building with `SCREENSHOT`
/// (`Configuration/Debug.xcconfig`). Covers already on screen keep theirs
/// until they load again.
enum ScreenshotArtwork {
    /// Where the Settings switch starts: on in a `SCREENSHOT` build.
    #if SCREENSHOT
    static let isOnByDefault = true
    #else
    static let isOnByDefault = false
    #endif

    static var isEnabled: Bool {
        if ProcessInfo.processInfo.arguments.contains("-ScreenshotArtwork") { return true }
        return UserDefaults.standard.object(forKey: AppStorageKeys.screenshotArtwork) as? Bool ?? isOnByDefault
    }

    /// The player background's gradient for `cover`, at the cover's size and
    /// scale so nothing laid out around it moves.
    static func gradient(for cover: UIImage) -> UIImage? {
        guard let colors = ArtworkMeshBackground.sampleColors(from: cover),
              let gradient = ArtworkMeshBackground.renderGradient(colors) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = cover.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: cover.size, format: format).image { context in
            context.cgContext.interpolationQuality = .high
            gradient.draw(in: CGRect(origin: .zero, size: cover.size))
        }
    }
}

/// The image pipeline's delegate in debug builds: Screenshot Artwork's hooks,
/// and Nuke's defaults for everything else.
final class ScreenshotArtworkPipelineDelegate: ImagePipeline.Delegate {
    /// The gradients' own memory cache, so flipping the switch either way
    /// never shows what the other setting left behind.
    private let gradients = ImageCache()

    func imageCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any ImageCaching)? {
        ScreenshotArtwork.isEnabled ? gradients : pipeline.configuration.imageCache
    }

    func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? {
        let decoder = pipeline.configuration.makeImageDecoder(context)
        guard let decoder, ScreenshotArtwork.isEnabled, context.request.userInfo[.realCover] == nil else {
            return decoder
        }
        return GradientDecoder(cover: decoder)
    }

    /// Keeps gradients off the disk. `image` is set when the pipeline stores
    /// a thumbnail or resized image rather than the downloaded data, and
    /// that image would be a gradient. The downloaded data is the real cover
    /// and is stored as usual.
    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline, completion: @escaping (Data?) -> Void) {
        completion(image != nil && ScreenshotArtwork.isEnabled ? nil : data)
    }
}

/// Decodes the cover as usual, then hands back its gradient instead. No
/// progressive previews, which would show the real cover while it loads, and
/// a cover with no gradient fails rather than appearing in a screenshot (its
/// view shows its placeholder).
private struct GradientDecoder: ImageDecoding {
    let cover: any ImageDecoding

    var isAsynchronous: Bool { cover.isAsynchronous }

    func decode(_ data: Data) throws -> ImageContainer {
        let decoded = try cover.decode(data)
        guard let gradient = ScreenshotArtwork.gradient(for: decoded.image) else {
            throw ImageDecodingError.unknown
        }
        return ImageContainer(image: gradient)
    }
}
#endif
