import Analytics
import Defaults
import Nuke
import SubscriptionKit
import UIKit

final class AppBootstrapper {
    static let shared = AppBootstrapper()
    var didLaunch = false

    func bootstrap() {
        UITextField.appearance().clearButtonMode = .whileEditing
        SubscriptionService.shared.initialize(key: CloudKeys.hasSubscription)
        Analytics.shared.configure(token: "343f1efbe07acecdefdcd6f71f351673", userID: SubscriptionService.shared.userID)
        RemoteFeatureFlags.shared.fetch()

        // First entry of the ordered selection list is the primary service.
        if let stored = UserDefaults.standard.string(forKey: AppStorageKeys.selectedSearchServices),
           let primary = stored.split(separator: ",").first {
            Analytics.shared.setSelection(metadata: ["MusicService": String(primary)])
        }

        configureNuke()
    }

    private func configureNuke() {
#if DEBUG
        // Screenshot Artwork (Settings ▸ Debug) swaps covers for gradients here.
        let delegate = ScreenshotArtworkPipelineDelegate()
#else
        let delegate: (any ImagePipeline.Delegate)? = nil
#endif
        let pipeline = ImagePipeline(delegate: delegate) {
            let imageCache = ImageCache.shared
            // Sized to the device: a Mac window shows forty-odd album covers
            // at once, and at a fixed 50 MB the cache held fewer than that,
            // so scrolling back re-decoded every cover from disk and coming
            // back to the grid reloaded the lot. A tenth of physical
            // memory, between 50 MB and 200 MB.
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            imageCache.costLimit = Int(min(max(physicalMemory / 10, 50 * 1024 * 1024), 200 * 1024 * 1024))
            imageCache.countLimit = 1000
            $0.imageCache = imageCache
            $0.dataCache = try? DataCache(name: "com.cue.imageCache")

            // Prefer cached data whenever possible
            $0.dataCachePolicy = .automatic

            // Optimize the DataLoader
            let config = URLSessionConfiguration.default
            config.urlCache = nil // disable URLCache, rely on Nuke's DataCache
            config.requestCachePolicy = .reloadIgnoringLocalCacheData // let Nuke handle caching
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 60
            config.waitsForConnectivity = false // fail fast

            $0.dataLoader = DataLoader(configuration: config)

            // No decoder override. One was here, `ImageDecoders.Default()`,
            // meant to "reduce memory footprint" — and it did the opposite:
            // built without the request's context it never saw the
            // `thumbnail` options the artwork views ask for, so every cover
            // was decoded at its original size (a 3000px Plex or Subsonic
            // cover is 36 MB) and downsampling was silently a no-op app-wide.
            // The registry's default decoder is the same class, built with
            // the context, so the thumbnail path works.
        }

        ImagePipeline.shared = pipeline
    }
}
