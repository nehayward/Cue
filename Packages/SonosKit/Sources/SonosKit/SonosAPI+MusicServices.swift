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
        default:
            nil
        }

        return content
    }

    private func handleMusic(url: URL, path: String, query: String?) -> MediaContent? {
        let paths = path.split(separator: "/").map(String.init)
        guard paths.count > 3, let type = ContentType(paths[1]), let id = paths.last else { return nil }

        if let querySplit = query?.split(separator: "=").map(String.init), querySplit.count > 1 {
            let songID = querySplit[1]
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

    private func parseTuneIn(components: URLComponents) -> MediaContent? {
        let paths = components.path.split(separator: "/").map(String.init)
        guard let pathID = paths.last, let id = pathID.components(separatedBy: "-").last else { return nil }
        return MediaContent(service: .tuneIn, id: id, type: .radio, location: components.url)
    }
}
