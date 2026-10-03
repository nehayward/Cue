extension String {
    /// The five XML entities decoded, as five `replacingOccurrences` passes
    /// in turn (`&lt;`, `&gt;`, `&amp;`, `&quot;`, `&apos;`) did, in one walk
    /// over the bytes. Every speaker response the groups poll reads comes
    /// through here, and the five passes took 12 times as long (more than
    /// twice as long in a debug build). Their result is kept exactly, quirk
    /// included: the `&amp;` pass ran before `&quot;` and `&apos;`, so
    /// `&amp;quot;` comes out as `"` while `&amp;lt;` stays `&lt;`.
    ///
    /// Plain byte comparisons rather than a helper matching names from
    /// arrays: that version was faster optimized but three times slower
    /// than the passes in a debug build.
    var unescaped: String {
        guard utf8.contains(UInt8(ascii: "&")) else { return self }
        var source = self
        return source.withUTF8 { bytes in
            let count = bytes.count
            let ampersand = UInt8(ascii: "&")
            // The byte at `index`, or 0 past the end.
            func at(_ index: Int) -> UInt8 { index < count ? bytes[index] : 0 }
            // Whether `a`, `b`, `c`, then `d` if given, then ";" come next,
            // from `index`.
            func spells(_ a: Character, _ b: Character, _ c: Character, _ d: Character?, at index: Int) -> Bool {
                at(index) == a.asciiValue && at(index + 1) == b.asciiValue && at(index + 2) == c.asciiValue
                    && (d == nil || at(index + 3) == d?.asciiValue)
                    && at(index + (d == nil ? 3 : 4)) == UInt8(ascii: ";")
            }
            // Decoding only ever shortens the text.
            return String(unsafeUninitializedCapacity: count) { output in
                var index = 0
                var written = 0
                while index < count {
                    let byte = bytes[index]
                    index += 1
                    guard byte == ampersand else {
                        output[written] = byte
                        written += 1
                        continue
                    }
                    var decoded = byte
                    if at(index + 1) == UInt8(ascii: "t"), at(index + 2) == UInt8(ascii: ";"),
                       at(index) == UInt8(ascii: "l") || at(index) == UInt8(ascii: "g") {
                        decoded = at(index) == UInt8(ascii: "l") ? UInt8(ascii: "<") : UInt8(ascii: ">")
                        index += 3
                    } else {
                        // `&amp;` was decoded before `&quot;` and `&apos;`, so
                        // one of those right after it decodes too.
                        let isAmp = spells("a", "m", "p", nil, at: index)
                        let name = isAmp ? index + 4 : index
                        if spells("q", "u", "o", "t", at: name) {
                            decoded = UInt8(ascii: "\"")
                            index = name + 5
                        } else if spells("a", "p", "o", "s", at: name) {
                            decoded = UInt8(ascii: "'")
                            index = name + 5
                        } else {
                            index = name
                        }
                    }
                    output[written] = decoded
                    written += 1
                }
                return written
            }
        }
    }

    /// Decodes XML entities exactly **once**, scanning left-to-right without
    /// re-processing what it just emitted.
    ///
    /// `unescaped` decodes as five sequential passes would, so a
    /// double-escaped sequence like `&amp;quot;` is collapsed all the way to a
    /// literal `"` (`&amp;`→`&`, then the resulting `&quot;`→`"`). For Sonos
    /// alarm metadata — DIDL that is escaped *inside* the already-escaped
    /// `CurrentAlarmList` — that over-decode injects bare quotes/angle brackets
    /// into attribute values and corrupts the surrounding XML. Decoding a single
    /// level turns `&amp;quot;` into `&quot;`, keeping the inner payload
    /// well-formed so a real `XMLParser` can read it.
    var xmlEntityDecodedOnce: String {
        guard contains("&") else { return self }
        var result = ""
        result.reserveCapacity(count)
        var index = startIndex
        while index < endIndex {
            guard self[index] == "&" else {
                result.append(self[index])
                index = self.index(after: index)
                continue
            }
            let rest = self[index...]
            if rest.hasPrefix("&lt;") { result.append("<"); index = self.index(index, offsetBy: 4) }
            else if rest.hasPrefix("&gt;") { result.append(">"); index = self.index(index, offsetBy: 4) }
            else if rest.hasPrefix("&amp;") { result.append("&"); index = self.index(index, offsetBy: 5) }
            else if rest.hasPrefix("&quot;") { result.append("\""); index = self.index(index, offsetBy: 6) }
            else if rest.hasPrefix("&apos;") { result.append("'"); index = self.index(index, offsetBy: 6) }
            else { result.append("&"); index = self.index(after: index) }
        }
        return result
    }

    var ampersandSafe: String {
        var xml = self
        xml = xml.replacingOccurrences(of: "&amp;", with: "%26")
        xml = xml.replacingOccurrences(of: "&", with: "%26")
        return xml
    }

    /// Escapes a URL for embedding as element text inside a pre-escaped DIDL
    /// string (the `&lt;DIDL-Lite …&gt;` metadata literals): the DIDL layer
    /// needs `&` as `&amp;`, which at the outer SOAP-escaped layer is
    /// `&amp;amp;` — the same double escape the `<res>` URIs already use.
    /// `ampersandSafe` (`&` → `%26`) corrupts URLs whose query string relies
    /// on `&` separators; Sonos round-trips the corrupted URL back as
    /// albumArtURI and the download 503s (seen with Sonos Radio's
    /// sali.sonos.superhi.fi artwork proxy).
    var didlEscaped: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&", with: "&amp;amp;")
    }
    
    var escaped: String {
        var xml = self
        xml = xml.replacingOccurrences(of: "&", with: "&amp;")
        xml = xml.replacingOccurrences(of: "<", with: "&lt;")
        xml = xml.replacingOccurrences(of: ">", with: "&gt;")
        return xml
    }

    var xmlAllowedString: String {
        var xml = self
        xml = xml.replacingOccurrences(of: " ", with: "&#32;")
        return xml
    }

    var encodeForSonos: String {
        let xml = self
        return xml
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: " ", with: "&#32;")
    }

    var encodeProgramURI: String {
        let xml = self
        return xml
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    var metaDataTitle: String {
        let xml = self
        return xml
            .replacingOccurrences(of: "&", with: "&amp;amp;")
    }
    
    func removingHTMLEntities() -> String {
        var result = self
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "/&gt;", with: ">")
        result = result.replacingOccurrences(of: "/&lt;", with: "<")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        return result
    }
}
