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
        if host?.contains("sali.sonos") == true {
            guard let inner = saliInnerImageURL() else { return self }
            return inner.replacingWidth(with: width) ?? self
        }
        if host?.contains("sonosradio.imgix.net") == true {
            return replacingWidth(with: width) ?? self
        }
        return self
    }

    /// Extracts the inner imgix URL from the sali proxy's `image` parameter.
    /// Handles both the healthy form and the corrupted legacy form written by
    /// builds before `didlEscaped` — those percent-encoded the query
    /// separators (`image?w=60%26image=…`), collapsing the whole query into a
    /// single unparseable `w` item. Repairing the separators lets stations
    /// queued by old builds self-heal instead of 503ing until re-queued.
    private func saliInnerImageURL() -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
        if let inner = innerImageURL(from: components) { return inner }

        guard let raw = components.percentEncodedQuery, raw.contains("%26") else { return nil }
        components.percentEncodedQuery = Self.repairingCorruptedSeparators(in: raw)
        return innerImageURL(from: components)
    }

    private func innerImageURL(from components: URLComponents) -> URL? {
        guard let inner = components.queryItems?.first(where: { $0.name == "image" })?.value,
              let innerURL = URL(string: inner),
              innerURL.scheme?.hasPrefix("http") == true else {
            return nil
        }
        return innerURL
    }

    /// Restores the outer `&` separators in a query whose separators were
    /// percent-encoded to `%26`. Only separators followed by a `name=` pair
    /// with a **literal** `=` are outer params; a `%26` segment without one
    /// (e.g. `auto%3Dformat`, whose `=` is still encoded) belongs inside the
    /// previous param's percent-encoded value and is kept as-is.
    private static func repairingCorruptedSeparators(in rawQuery: String) -> String {
        let segments = rawQuery.components(separatedBy: "%26")
        guard segments.count > 1 else { return rawQuery }
        var params: [String] = []
        for segment in segments {
            if segment.contains("=") || params.isEmpty {
                params.append(segment)
            } else {
                params[params.count - 1] += "%26" + segment
            }
        }
        return params.joined(separator: "&")
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
