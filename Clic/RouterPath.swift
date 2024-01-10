import Foundation
import SwiftUI
import Observation
import SonosKit

enum Router {
    case subscribe
    case device
    case search

    init?(_ host: String) {
        switch host {
        case "subscribe":
            self = .subscribe
        case "device":
            self = .device
        default:
            return nil
        }
    }
}

struct Route: Equatable, Identifiable, Hashable {
    let id: String
    var search: Bool
}


@Observable public class RouterPath {
    static var shared = RouterPath()

    var path: [RouterDestination] = []
    var presentedSheet: SheetDestination?
    
    private let sonosService: SonosService

    public init(sonosService: SonosService = .shared) {
        self.sonosService = sonosService
    }

    @MainActor
    public func navigate(to: RouterDestination) {
        path.append(to)
    }

    public func handle(url: URL) -> () {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        if components.host?.lowercased() == "subscribe" {
            presentedSheet = .paywall
            return
        }

        if components.host?.lowercased() == "search", let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
            if sonosService.groups.contains(where:  { $0.coordinatorRoom.id == id} ) {
//                path.append(.player(group: group))
//                presentedSheet = .search(group: group)
                return
            }
            Task {
                try await sonosService.fetch(useCache: true)
                if sonosService.groups.contains(where:  { $0.coordinatorRoom.id == id} ) {
//                    selected = Route(id: id, search: true)
//                    path.append(.player(group: group.))
                }
            }
        }

        if components.host?.lowercased() == "device", let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty {
            if sonosService.groups.contains(where:  { $0.coordinatorRoom.id == id} ) {
//                selected = Route(id: id, search: false)
                return
            }
            Task {
                try await sonosService.fetch(useCache: true)
                if sonosService.groups.contains(where:  { $0.coordinatorRoom.id == id} ) {
//                    selected = Route(id: id, search: false)
                }
            }
        }

        if components.host?.lowercased() == "scene", let name = components.queryItems?.first(where: { $0.name == "name" })?.value, !name.isEmpty {
//            guard let scene = scenes.first(where: { $0.name == name }) else { return }
//            Task {
//                alertService.showAlert(with: "Running \(scene.name)")
//                try await sonosService.runScene(scene)
//            }
        }

        if components.host?.lowercased() == "play", let paths = components.string?.split(separator: "/").map(String.init).dropFirst(2) {


            //            await sonosService.que
            //            guard let typeString = paths.first, let type = ContentType(typeString), let id = paths.last else { return nil }
            //            return MediaContent(service: .spotify, id: id, type: type, location: url)

            //            let spotifyPlaylistURL = URL(string: "https://open.spotify.com/playlist/6zKUeBJeJQODG5o2PzxRsZ")!
            //            XCTAssertEqual(sonosAPI.parse(url: spotifyPlaylistURL), MediaContent(service: .spotify, id: "6zKUeBJeJQODG5o2PzxRsZ", type: .playlist, location: spotifyPlaylistURL))
            //
            //            let spotifyAlbumURL = URL(string: "https://open.spotify.com/album/7fJJK56U9fHixgO0HQkhtI")!
            //            XCTAssertEqual(sonosAPI.parse(url: spotifyAlbumURL), MediaContent(service: .spotify, id: "7fJJK56U9fHixgO0HQkhtI", type: .album, location: spotifyAlbumURL))
            //
            //            let spotifyArtistURL = URL(string: "https://open.spotify.com/artist/6M2wZ9GZgrQXHCFfjv46we")!
            //            XCTAssertEqual(sonosAPI.parse(url: spotifyArtistURL), MediaContent(service: .spotify, id: "6M2wZ9GZgrQXHCFfjv46we", type: .artist, location: spotifyArtistURL))
            //
            //            let spotifyTrackURL = URL(string: "https://open.spotify.com/track/5bGNsC7FTQ3WZzz0XYOmvZ")!
            //            XCTAssertEqual(sonosAPI.parse(url: s
            //            Task {
            //                alertService.showAlert(with: "Running \(scene.name)")
            //                try await sonosService.runScene(scene)
            //            }
        }
    }
}

