extension String {
    var unescaped: String {
        var xml = self
        xml = xml.replacingOccurrences(of: "&lt;", with: "<")
        xml = xml.replacingOccurrences(of: "&gt;", with: ">")
        xml = xml.replacingOccurrences(of: "&amp;", with: "&")
        xml = xml.replacingOccurrences(of: "&quot;", with: "\"")
        xml = xml.replacingOccurrences(of: "&apos;", with: "'")
        return xml
    }
    
    /// Decodes XML entities exactly **once**, scanning left-to-right without
    /// re-processing what it just emitted.
    ///
    /// `unescaped` runs five sequential `replacingOccurrences` passes, so a
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
