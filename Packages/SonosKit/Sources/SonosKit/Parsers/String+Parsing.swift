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
    
    var ampersandSafe: String {
        var xml = self
        xml = xml.replacingOccurrences(of: "&amp;", with: "%26")
        xml = xml.replacingOccurrences(of: "&", with: "%26")
        return xml
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
