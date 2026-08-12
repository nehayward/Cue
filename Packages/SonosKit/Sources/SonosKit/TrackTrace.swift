import Foundation

/// Debug-only tracing for the track-change path: who writes `room.track`, how
/// often, and how many times the artwork actually swaps as a result.
///
/// One channel for the whole path — SonosKit's writers and the app's
/// `ArtworkView` both log here — so a single track change reads as one
/// timeline. Compiled out of release builds.
///
/// Xcode console: filter on `[track]`, `[art]`, or `[fade]`.
public enum TrackTrace {
    /// `@autoclosure` so the interpolation isn't built at all in release.
    public static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }

    /// URLs here are long Sonos proxy or CDN paths; the tail is the part that
    /// differs between two loads of the same artwork.
    public static func brief(_ url: URL?) -> String {
        guard let url else { return "nil" }
        return String(url.absoluteString.suffix(44))
    }
}
