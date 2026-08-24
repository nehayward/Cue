import Analytics
import Defaults
import Nuke
import SubscriptionKit
import TipKit

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

        try? Tips.configure([.displayFrequency(.immediate)])
        configureNuke()
    }

    private func configureNuke() {
        let pipeline = ImagePipeline {
            let imageCache = ImageCache.shared
            imageCache.costLimit = 1024 * 1024 * 50 // 50 MB max memory usage
            imageCache.countLimit = 500             // Store up to 300 images
            $0.imageCache = imageCache
            $0.dataCache = try? DataCache(name: "com.clic.imageCache")

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

            // Reduce memory footprint
            $0.makeImageDecoder = { _ in
                return ImageDecoders.Default()
            }
        }

        ImagePipeline.shared = pipeline
    }
}
