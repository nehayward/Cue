import Defaults
import Foundation
import SwiftUI

/// Pulls release metadata (version + one-line headline) from clic.dance so
/// the in-app "What's New" banner can show a current pitch without an app
/// release. Always asks for the user's bundle version — never falls back to
/// the newest release — so an old device only ever sees notes for the build
/// it actually has. If the per-version JSON 404s, the banner stays hidden.
enum LatestReleaseFetcher {
    private static let host = "https://clic.dance"

    private struct Payload: Decodable {
        let version: String
        let headline: String
    }

    static func refresh() async {
        let bundleVersion = OSEnvironment.versionInfo
        guard let url = URL(string: "\(host)/api/releases/\(bundleVersion).json") else { return }

        if let payload = await fetch(url) {
            store(payload)
        } else {
            // 404 (or any other failure): clear any previously-cached
            // release info so the banner won't render against stale data
            // for a version we no longer have notes for.
            clear()
        }
    }

    private static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Defaults.AppStorageKeys.latestReleaseVersion)
        defaults.removeObject(forKey: Defaults.AppStorageKeys.latestReleaseHeadline)
    }

    private static func fetch(_ url: URL) async -> Payload? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 8

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        return payload
    }

    private static func store(_ payload: Payload) {
        let defaults = UserDefaults.standard
        defaults.set(payload.version, forKey: Defaults.AppStorageKeys.latestReleaseVersion)
        defaults.set(payload.headline, forKey: Defaults.AppStorageKeys.latestReleaseHeadline)
    }
}
