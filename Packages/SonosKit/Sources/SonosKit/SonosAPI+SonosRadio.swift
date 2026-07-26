import Foundation

extension SonosAPI {
    /// Resolves a music service's SMAPI endpoint by asking a Sonos player for
    /// its `ListAvailableServices` descriptor list and reading the matching
    /// service's `SecureUri`. Used to reach first-party services like Sonos
    /// Radio (service id `303`) that have no public REST API.
    func availableServiceURI(IP: String, serviceID: String) async -> URL? {
        let arguments: OrderedKeys = []
        guard let (data, response) = try? await sendSoapRequest(
            ip: IP,
            action: "ListAvailableServices",
            arguments: arguments,
            endpoint: "MusicServices"
        ) else {
            return nil
        }
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        let xml = String(decoding: data, as: UTF8.self)
        return AvailableServicesParser.secureURI(in: xml, serviceID: serviceID)
    }
}

/// Parses the (entity-escaped) `AvailableServiceDescriptorList` returned by
/// `ListAvailableServices` for a given service id.
enum AvailableServicesParser {
    static func secureURI(in xml: String, serviceID: String) -> URL? {
        // The descriptor list is XML-escaped inside the SOAP response; unescape
        // it so the `<Service .../>` attributes become parseable.
        let unescaped = xml
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")

        // Isolate the <Service Id="<serviceID>" ...> element.
        let entries = unescaped.components(separatedBy: "<Service ")
        for entry in entries {
            guard let id = attribute("Id", in: entry), id == serviceID else { continue }
            // Prefer the secure endpoint, fall back to the plain Uri.
            if let secure = attribute("SecureUri", in: entry), let url = URL(string: secure) {
                return url
            }
            if let uri = attribute("Uri", in: entry), let url = URL(string: uri) {
                return url
            }
        }
        return nil
    }

    private static func attribute(_ name: String, in entry: String) -> String? {
        let pattern = "\(name)=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: entry, range: NSRange(entry.startIndex..., in: entry)),
              let range = Range(match.range(at: 1), in: entry) else {
            return nil
        }
        return String(entry[range])
    }
}
