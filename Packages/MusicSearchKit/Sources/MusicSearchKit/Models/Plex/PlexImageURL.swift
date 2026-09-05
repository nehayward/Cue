import Foundation

/// The sizes Cue asks Plex for. Plex keeps the original embedded cover —
/// often 1500–3000px — and serves it as-is from `/library/metadata/…/thumb`,
/// so every row was downloading and holding megabytes of image it showed at
/// 50pt. `/photo/:/transcode` resizes on the server instead, the same way
/// the Plex web app fills its own grids.
public enum PlexImageSize {
    /// Rows and grid tiles: crisp up to 100pt on a 3x screen.
    public static let thumbnail = 300
    /// The player and detail heroes, and what Sonos is handed as the album
    /// art for a queued track. Nothing in Cue draws bigger than this.
    public static let artwork = 1200
}

public extension URL {
    /// This Plex image, resized on the server to fit `size` pixels square.
    ///
    /// Takes the token-carrying URL `PlexAPI` builds (`base/library/metadata/
    /// 1/thumb/2?X-Plex-Token=…`) and re-points it at the transcoder with
    /// the original path as its `url`. Anything that isn't recognisably a
    /// Plex image URL — no token, no `/library/` or `/playlists/` path —
    /// comes back untouched, as does one that is already a transcode.
    func plexResized(to size: Int) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "X-Plex-Token" })?.value,
              !components.path.contains("/photo/:/transcode"),
              let imagePath = Self.plexImagePath(in: components.path)
        else { return self }

        // A server behind a reverse proxy can carry a path prefix; it stays
        // in front of the transcode endpoint, not inside the `url` parameter.
        let prefix = String(components.path.dropLast(imagePath.count))
        components.path = prefix + "/photo/:/transcode"
        components.queryItems = [
            URLQueryItem(name: "width", value: "\(size)"),
            URLQueryItem(name: "height", value: "\(size)"),
            // Fit inside the box without cropping, and don't blow a small
            // image up to fill it.
            URLQueryItem(name: "minSize", value: "1"),
            URLQueryItem(name: "upscale", value: "0"),
            URLQueryItem(name: "url", value: imagePath),
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]
        return components.url ?? self
    }

    /// The Plex-relative image path inside a possibly prefixed path — from
    /// the last `/library/` or `/playlists/` on, which is where Plex's own
    /// image paths start.
    private static func plexImagePath(in path: String) -> String? {
        ["/library/", "/playlists/"]
            .compactMap { path.range(of: $0, options: .backwards)?.lowerBound }
            .min()
            .map { String(path[$0...]) }
    }
}
