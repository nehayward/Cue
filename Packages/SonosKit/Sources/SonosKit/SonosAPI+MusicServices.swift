import Foundation

extension SonosAPI {
    func parse(url: URL) -> MediaContent? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        if let scheme = components.scheme, scheme.lowercased() == "clic" {
            let paths = components.path.split(separator: "/").map(String.init)
            guard paths.count > 2, let service = MusicService(service: paths[0]), let type = ContentType(paths[1]) else { return nil }
            let id = paths[2]
            return MediaContent(service: service, id: id, type: type, location: nil)
        }

        let content: MediaContent? = switch components.host {
        case let .some(host) where host.contains("spotify"):
            handleSpotify(url: url, path: components.path)
        case let .some(host) where host.contains("apple"):
            handleMusic(url: url, path: components.path, query: components.query)
        case let .some(host) where host.contains("tidal"):
            parseTidal(url: url, path: components.path)
        case let .some(host) where host.contains("tunein"):
            parseTuneIn(components: components)
        case let .some(host) where host.contains("deezer"):
            parseDeezer(url: url, path: components.path)
        default:
            nil
        }

        return content
    }

    private func handleMusic(url: URL, path: String, query: String?) -> MediaContent? {
        let paths = path.split(separator: "/").map(String.init)
        // Accept both `/<storefront>/<type>/<slug>/<id>` (4 parts) and the slug-less
        // `/<storefront>/<type>/<id>` (3 parts) form Apple Music sometimes generates.
        guard paths.count >= 3, let type = ContentType(paths[1]), let id = paths.last else { return nil }
        
        // Split query into individual parameters
        let queryParams = query?.components(separatedBy: "&").reduce(into: [String: String]()) { result, param in
            let parts = param.components(separatedBy: "=")
            if parts.count == 2 {
                result[parts[0]] = parts[1]
            }
        }
        
        // If we have an 'i' parameter, use that as the song ID
        if let songID = queryParams?["i"] {
            return MediaContent(service: .apple, id: songID, type: .track, location: url)
        }
        
        return MediaContent(service: .apple, id: id, type: type, location: url)
    }

    private func handleSpotify(url: URL, path: String) -> MediaContent? {
        let paths = path.split(separator: "/").map(String.init)
        guard let typeString = paths.first, let type = ContentType(typeString), let id = paths.last else { return nil }
        return MediaContent(service: .spotify, id: id, type: type, location: url)
    }

    private func parseTidal(url: URL, path: String) -> MediaContent? {
        let paths = path.split(separator: "/").map(String.init)
        guard paths.count > 2, let type = ContentType(paths[1]), let id = paths.last else { return nil }
        return MediaContent(service: .tidal, id: id, type: type, location: url)
    }

    private func parseDeezer(url: URL, path: String) -> MediaContent? {
        var paths = path.split(separator: "/").map(String.init)
        // Strip locale prefix like "us", "gb", "fr" (2-letter country code)
        if let first = paths.first, first.count == 2, first.allSatisfy(\.isLetter) {
            paths.removeFirst()
        }
        // paths is now [type, id] e.g. ["playlist", "2249258602"]
        guard paths.count >= 2,
              let type = ContentType(paths[0]),
              let id = paths.last else { return nil }
        return MediaContent(service: .deezer, id: id, type: type, location: url)
    }

    private func parseTuneIn(components: URLComponents) -> MediaContent? {
        let paths = components.path.split(separator: "/").map(String.init)
        guard let pathID = paths.last, let id = pathID.components(separatedBy: "-").last else { return nil }
        return MediaContent(service: .tuneIn, id: id, type: .radio, location: components.url)
    }
}
