#if DEBUG
import Foundation
import MusicSearchKit
import os
import Security
import SonosKit

/// Debug builds stay signed in to Subsonic and Audiobookshelf. The login
/// signed in with here is kept in the keychain, which outlives deleting the
/// app, and signed in with again whenever the service's own is lost: a
/// fresh install (each keeps its server and user in UserDefaults, which go
/// with the app), or Audiobookshelf turning its refresh token away (spent
/// by a renewal whose answer never came back, as when Xcode relaunches Cue
/// mid-request, or 30 days unused). Signing out in the service's sheet
/// forgets it.
///
/// Only a password sign-in can be kept: single sign-on has none to replay.
/// Each is logged under `dance.cue` `accounts`.
@MainActor
enum DebugAccounts {
    enum Service: String, CaseIterable {
        case subsonic
        case audiobookshelf

        var title: String {
            switch self {
            case .subsonic: "Subsonic"
            case .audiobookshelf: "Audiobookshelf"
            }
        }
    }

    struct Login: Codable, Equatable {
        var address: String
        var username: String
        var password: String
    }

    /// At launch: signs in again where the login is gone, keeps a Subsonic
    /// login made before this build kept them, and stands by for
    /// Audiobookshelf's refresh token.
    static func start() {
        restoreSubsonic()
        let shelf = AudiobookshelfAPI.shared
        shelf.signInAgain = {
            await signInToAudiobookshelf(because: "the refresh token was turned away")
        }
        if !shelf.isConfigured, kept(.audiobookshelf) != nil {
            Task {
                guard await signInToAudiobookshelf(because: "not signed in at launch") else { return }
                CoreFeatures.shared.enabledServices(.audiobookshelf).wrappedValue = true
                await AudiobookshelfBrowseService.shared.refresh()
            }
        }
    }

    private static func restoreSubsonic() {
        let subsonic = SubsonicAPI.shared
        if subsonic.isConfigured {
            // The password is in Subsonic's own keychain item, so a login
            // from before is kept with nothing to type.
            keep(.subsonic, address: subsonic.serverAddress, username: subsonic.username, password: subsonic.password)
            return
        }
        guard let login = kept(.subsonic) else { return }
        subsonic.serverAddress = login.address
        subsonic.username = login.username
        subsonic.password = login.password
        CoreFeatures.shared.enabledServices(.subsonic).wrappedValue = true
        Task { await SubsonicBrowseService.shared.refresh() }
        log.notice("subsonic: signed in again as \(login.username, privacy: .public) at \(login.address, privacy: .public)")
    }

    @discardableResult
    private static func signInToAudiobookshelf(because reason: String) async -> Bool {
        guard let login = kept(.audiobookshelf) else { return false }
        let check = await AudiobookshelfAPI.shared.signIn(address: login.address, username: login.username, password: login.password)
        switch check.result {
        case .success:
            log.notice("audiobookshelf: signed in again as \(login.username, privacy: .public) at \(check.address ?? login.address, privacy: .public), as \(reason, privacy: .public)")
            return true
        case let .failure(message):
            log.error("audiobookshelf: couldn't sign in again (\(reason, privacy: .public)): \(message, privacy: .public)")
            return false
        }
    }

    // MARK: - Kept logins

    /// The services a login is kept for, for Settings ▸ Debug.
    static var keptServices: [Service] {
        Service.allCases.filter { kept($0) != nil }
    }

    /// Keeps a login the server has just taken. Written only when it
    /// differs from the one kept.
    static func keep(_ service: Service, address: String, username: String, password: String) {
        guard !address.isEmpty, !username.isEmpty, !password.isEmpty else { return }
        let login = Login(address: address, username: username, password: password)
        guard kept(service) != login, let data = try? JSONEncoder().encode(login) else { return }
        let base = query(for: service)
        SecItemDelete(base as CFDictionary)
        var attributes = base
        attributes[kSecValueData as String] = data
        // After first unlock, as the services' own items: Cue can launch in
        // the background while the phone is locked. This device only, so the
        // password stays out of backups.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess {
            log.notice("\(service.rawValue, privacy: .public): kept the login for \(username, privacy: .public) at \(address, privacy: .public)")
        } else {
            log.error("\(service.rawValue, privacy: .public): couldn't keep the login: \(status)")
        }
    }

    /// Forgets the login kept, as the service is signed out of.
    static func forget(_ service: Service) {
        let status = SecItemDelete(query(for: service) as CFDictionary)
        if status == errSecSuccess {
            log.notice("\(service.rawValue, privacy: .public): forgot the kept login")
        }
    }

    static func kept(_ service: Service) -> Login? {
        var query = query(for: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Login.self, from: data)
    }

    private static func query(for service: Service) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dance.cue.debug.accounts",
            kSecAttrAccount as String: service.rawValue
        ]
    }

    private static let log = Logger(subsystem: "dance.cue", category: "accounts")
}
#endif
