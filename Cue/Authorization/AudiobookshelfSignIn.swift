import AuthenticationServices
import MusicSearchKit
import SonosKit
import SwiftUI

/// Signing in to an Audiobookshelf server: the fields, the ways in the
/// address offers (a password, single sign-on), the sign-in itself and what
/// a login kept switches on. Settings' sheet (`AudiobookshelfManagementView`)
/// and onboarding's page (`AudiobookshelfSetupStep`) lay it out each their
/// own way, on the same logic.
///
/// The password is only sent to sign in. What's kept is the server's
/// tokens, in the keychain (see `AudiobookshelfAPI`).
@MainActor
@Observable
final class AudiobookshelfSignIn {
    var serverAddress = ""
    var username = ""
    var password = ""
    private(set) var isConnecting = false
    private(set) var result: AudiobookshelfAPI.LoginResult?
    /// The ways in the address offers, read as it's typed.
    private(set) var methods: AudiobookshelfAPI.SignInMethods?

    @ObservationIgnored private let shelf = AudiobookshelfAPI.shared

    var isConfigured: Bool { shelf.isConfigured }

    /// Why the last try was turned down, if it was.
    var failure: String? {
        if case let .failure(message) = result { message } else { nil }
    }

    var canConnect: Bool {
        !isConnecting && !serverAddress.isEmpty && !username.isEmpty
    }

    /// A different server or user than the one signed in, so there's a
    /// sign-in to make. The password isn't kept, so it doesn't count.
    var hasUnsavedEdits: Bool {
        serverAddress != shelf.serverAddress || username != shelf.username || !password.isEmpty
    }

    /// One action, never both, as on the Subsonic sheet.
    var showsSignOut: Bool {
        isConfigured && !(hasUnsavedEdits && canConnect)
    }

    /// Single sign-on, when the address offers it and there's a sign-in to
    /// make.
    var offersSingleSignOn: Bool {
        methods?.singleSignOn == true && !showsSignOut
    }

    var singleSignOnTitle: String {
        methods?.singleSignOnTitle ?? "Sign In with Single Sign-On"
    }

    /// The stored server and user in the fields, as the page opens.
    func loadStored() {
        serverAddress = shelf.serverAddress
        username = shelf.username
    }

    /// Which ways in the address offers, once typing pauses. Run from a
    /// `.task(id:)` on the address, which cancels it on the next keystroke.
    func readMethods() async {
        let address = serverAddress
        guard !address.isEmpty else {
            methods = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        let found = await shelf.signInMethods(address: address)
        guard !Task.isCancelled else { return }
        withAnimation { methods = found }
    }

    /// Reduces a pasted browser URL to the server's root, in place. A
    /// scheme the user didn't type stays off until signing in settles it.
    func tidyAddress() {
        guard var tidied = AudiobookshelfURLs.normalizedAddress(serverAddress) else { return }
        if !serverAddress.contains("://"), tidied.hasPrefix("http://") {
            tidied.removeFirst("http://".count)
        }
        serverAddress = tidied
    }

    @discardableResult
    func connect() async -> Bool {
        tidyAddress()
        isConnecting = true
        let check = await shelf.signIn(address: serverAddress, username: username, password: password)
        isConnecting = false
        result = check.result
        guard check.result == .success, let address = check.address else { return false }
        signedIn(at: address)
        return true
    }

    /// Signs in through the server's single sign-on: its provider's page in
    /// a web sign-in session, which hands back the address it ends on.
    @discardableResult
    func connectWithSingleSignOn(using session: WebAuthenticationSession) async -> Bool {
        tidyAddress()
        isConnecting = true
        let check = await shelf.signInWithSingleSignOn(address: serverAddress) { page in
            try? await session.authenticate(
                using: page,
                callbackURLScheme: AudiobookshelfAPI.singleSignOnCallbackScheme,
                preferredBrowserSession: .shared
            )
        }
        isConnecting = false
        result = check.result
        guard check.result == .success, let address = check.address else { return false }
        username = shelf.username
        signedIn(at: address)
        return true
    }

    /// The login kept: Audiobookshelf on, and its books read.
    private func signedIn(at address: String) {
        serverAddress = address
        password = ""
        CoreFeatures.shared.enabledServices(.audiobookshelf).wrappedValue = true
        Task { await AudiobookshelfBrowseService.shared.refresh() }
    }

    func signOut() async {
        isConnecting = true
        await shelf.signOut()
        isConnecting = false
        serverAddress = ""
        username = ""
        password = ""
        result = nil
        AudiobookshelfBrowseService.shared.clear()
        AudiobookProgressStore.shared.forgetAll(of: .audiobookshelf)
        CoreFeatures.shared.enabledServices(.audiobookshelf).wrappedValue = false
    }
}
