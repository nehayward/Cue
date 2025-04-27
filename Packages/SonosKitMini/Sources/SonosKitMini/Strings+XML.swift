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
}
