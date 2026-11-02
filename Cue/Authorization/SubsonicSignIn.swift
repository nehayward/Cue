import MusicSearchKit
import SonosKit
import SwiftUI

/// Signing in to a Subsonic-compatible server: the fields, the check
/// against the server, and what a login kept switches on. Settings' sheet
/// (`SubsonicManagementView`) and onboarding's page (`SubsonicSetupStep`)
/// lay it out each their own way, on the same logic.
@MainActor
@Observable
final class SubsonicSignIn {
    var serverAddress = ""
    var username = ""
    var password = ""
    private(set) var isConnecting = false
    private(set) var result: SubsonicAPI.PingResult?

    @ObservationIgnored private let subsonic = SubsonicAPI.shared

    var isConfigured: Bool { subsonic.isConfigured }

    /// Why the last try was turned down, if it was.
    var failure: String? {
        if case let .failure(message) = result { message } else { nil }
    }

    var canConnect: Bool {
        !isConnecting && !serverAddress.isEmpty && !username.isEmpty && !password.isEmpty
    }

    /// Fields differ from what's stored, so there is something to save.
    var hasUnsavedEdits: Bool {
        serverAddress != subsonic.serverAddress
            || username != subsonic.username
            || password != subsonic.password
    }

    /// One action, never both. Connect appears only when there is a complete
    /// edit to save, so a connected user who clears a field still has
    /// Disconnect — gating purely on "edited" stranded them with a Connect
    /// button their empty field had already disabled.
    var showsDisconnect: Bool {
        isConfigured && !(hasUnsavedEdits && canConnect)
    }

    /// The stored login in the fields, as the page opens.
    func loadStored() {
        serverAddress = subsonic.serverAddress
        username = subsonic.username
        password = subsonic.password
    }

    /// Reduces a pasted browser URL to the server's REST root, in place, so
    /// the field shows the address that will actually be used. A scheme the
    /// user didn't type stays off until connecting settles it, since a public
    /// name is tried over HTTPS first (`SubsonicAPI.checkLogin`).
    func tidyAddress() {
        guard var tidied = SubsonicAPI.normalizedAddress(serverAddress) else { return }
        if !serverAddress.contains("://"), tidied.hasPrefix("http://") {
            tidied.removeFirst("http://".count)
        }
        serverAddress = tidied
    }

    /// Verifies the login against the server and stores it only if the server
    /// accepts it — a rejected password never replaces a working one.
    @discardableResult
    func connect() async -> Bool {
        tidyAddress()
        isConnecting = true
        let check = await subsonic.checkLogin(address: serverAddress, username: username, password: password)
        isConnecting = false
        result = check.result
        guard check.result == .success, let address = check.address else { return false }

        // The address that answered, scheme and all.
        serverAddress = address
        subsonic.serverAddress = address
        subsonic.username = username
        subsonic.password = password
        // Anything cached from a previous server belongs to that server.
        MusicSearchService.shared.clearSubsonicSongCache()
        // A working server means the service is authorized — surface it in
        // search and browse right away.
        CoreFeatures.shared.enabledServices(.subsonic).wrappedValue = true
        Task { await SubsonicBrowseService.shared.refresh() }
        return true
    }

    func disconnect() {
        serverAddress = ""
        username = ""
        password = ""
        result = nil
        subsonic.serverAddress = ""
        subsonic.username = ""
        subsonic.password = ""
        MusicSearchService.shared.clearSubsonicSongCache()
        // Mirror the connect path, which enables the service — otherwise the
        // Settings toggle stays visually on for a service that can't play.
        CoreFeatures.shared.enabledServices(.subsonic).wrappedValue = false
    }
}
