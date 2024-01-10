import CloudStorage
import RevenueCat
import RevenueCatUI
import SonosKit
import SubscriptionKit
import StoreKit
import SwiftUI
import WidgetKit

@main
struct ClicApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @Environment(\.scenePhase) var scenePhase
    @Environment(\.requestReview) var requestReview
    @Environment(\.liveActivityManager) var liveActivityManager

    @State private var router: RouterPath = RouterPath.shared
    @State private var selected: Route?
    @State private var subscriptionService = SubscriptionService()
    @State private var sonosService = SonosService.shared
    @State private var alertService = AlertService()

    @CloudStorage("com.clic.subscriptions") private var activeSubscription: Bool = false
    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some Scene {
        WindowGroup {
            DeviceListMainView(selected: $selected)
                .environment(sonosService)
                .environment(subscriptionService)
                .environment(alertService)
                .onOpenURL(perform: handle)
                .withSheetDestinations(sheetDestinations: $router.presentedSheet)
                .task {
                    subscriptionService.monitorChanges()
                }
        }
        .onChange(of: scenePhase) {
            handleScenePhase(scenePhase)
        }
        .onChange(of: sonosService.sorted.map(\.coordinatorRoom.isPlaying), initial: false) {
            guard subscriptionService.subscription.isActive else { return }
            liveActivityManager.createActivity()
        }
        .onChange(of: subscriptionService.subscription, initial: true) { oldValue, newValue in
            activeSubscription =  newValue.isActive
        }
    }

    @MainActor
    private func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            sonosService.monitor()
            if !subscriptionService.subscription.isActive {
                return
            }
            
            Task {
                await liveActivityManager.refresh(type: .refresh)
            }

            Task {
                try? await subscriptionService.checkSubscription()
            }

            guard ReviewService().askForRequest() else { return }
            requestReview()

//            // MARK: Add back when monitoring is fixed
//            Task { @MainActor in
//                try? await sonosService.updateGroupsCheckPlayback()
//
//                if selected == nil {
//                    let playingGroups = sonosService.groups.filter(\.coordinatorRoom.isPlaying)
//                    if playingGroups.count == 1, let groupPlaying = playingGroups.first {
//                        try await Task.sleep(for: .milliseconds(200))
//                        alertService.showAlert(with: "Jumped to \(groupPlaying.coordinatorRoom.name)")
//                        selected = groupPlaying.coordinatorID
//                    }
//                }
//            }
        case .inactive:
            print("Inactive")
            WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
            Task {
                await liveActivityManager.refresh(type: .refresh)
            }
        case .background:
            print("Background")
            Task {
                sonosService.sonosPulse.cancel()
            }
        @unknown default:
            break
        }
    }

    private func handle(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        if components.host?.lowercased() == "subscribe" {
            RouterPath.shared.presentedSheet = .paywall
            return
        }

        if components.host?.lowercased() == "search", let id = components.queryItems?.first(where: { $0.name == "id" })?.value {
            if sonosService.groups.contains(where:  { $0.coordinatorRoom.id == id} ) {
                selected = Route(id: id, search: true)
                return
            }
            Task {
                try await sonosService.fetch(useCache: true)
                if sonosService.groups.contains(where:  { $0.coordinatorRoom.id == id} ) {
                    selected = Route(id: id, search: true)
                }
            }
        }

        if components.host?.lowercased() == "device", let id = components.queryItems?.first(where: { $0.name == "id" })?.value, !id.isEmpty {
            if sonosService.groups.contains(where:  { $0.coordinatorRoom.id == id} ) {
                selected = Route(id: id, search: false)
                return
            }
            Task {
                try await sonosService.fetch(useCache: true)
                if sonosService.groups.contains(where:  { $0.coordinatorRoom.id == id} ) {
                    selected = Route(id: id, search: false)
                }
            }
        }

        if components.host?.lowercased() == "scene", let name = components.queryItems?.first(where: { $0.name == "name" })?.value, !name.isEmpty {
            guard let scene = scenes.first(where: { $0.name == name }) else { return }
            Task {
                alertService.showAlert(with: "Running \(scene.name)")
                try await sonosService.runScene(scene)
            }
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

class AppDelegate: NSObject, UIApplicationDelegate {

}
