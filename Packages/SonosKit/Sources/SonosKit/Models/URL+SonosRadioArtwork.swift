import Foundation

public extension URL {
    /// Sonos Radio artwork URLs arrive sized for list rows: SMAPI search
    /// results and the round-tripped `albumArtURI` point at the
    /// `sali.sonos.superhi.fi` proxy with `w=60`, which is far too small for
    /// the player and mini player. Unwrap the proxy to the inner imgix URL —
    /// which also sidesteps the proxy's flaky 503s — and request `width`
    /// instead; a direct `sonosradio.imgix.net` URL just gets its `w` bumped.
    /// Any other URL is returned unchanged, so this is safe to apply at the
    /// parser level where TuneIn/other radio art flows through too.
    func sonosRadioArtwork(width: Int = 800) -> URL {
        // Proxy form: https://sali.sonos.superhi.fi/image?w=60&image=<encoded imgix URL>
        if host?.contains("sali.sonos") == true,
           let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
           let inner = components.queryItems?.first(where: { $0.name == "image" })?.value,
           let innerURL = URL(string: inner),
           innerURL.scheme?.hasPrefix("http") == true {
            return innerURL.replacingWidth(with: width) ?? self
        }
        if host?.contains("sonosradio.imgix.net") == true {
            return replacingWidth(with: width) ?? self
        }
        return self
    }

    private func replacingWidth(with width: Int) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
        var items = components.queryItems ?? []
        if let index = items.firstIndex(where: { $0.name == "w" }) {
            items[index].value = String(width)
        } else {
            items.append(URLQueryItem(name: "w", value: String(width)))
        }
        components.queryItems = items
        return components.url
    }
}
