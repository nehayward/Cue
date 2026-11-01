import AuthenticationServices
import MusicSearchKit
import SwiftUI
import SonosKit

/// Sign-in for an Audiobookshelf server. Like Subsonic, there's no
/// Sonos-side account: the login entered here is the whole setup, and the
/// device or a speaker plays the books straight from the server.
///
/// The password is only sent to sign in. What's kept is the server's
/// tokens, in the keychain (see `AudiobookshelfAPI`). A server with single
/// sign-on offers it under the password's Sign In, once its status says so;
/// the provider's page opens in a web sign-in session, with Safari's
/// cookies, so an account already signed in there goes straight through.
struct AudiobookshelfManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    /// The fields and the sign-in itself, shared with onboarding's page.
    @State private var signIn = AudiobookshelfSignIn()

    private enum Field { case address, username, password }
    @FocusState private var focused: Field?

    var body: some View {
        @Bindable var signIn = signIn
        NavigationStack {
            List {
                Section {
                    TextField("nas.local:13378", text: $signIn.serverAddress)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused, equals: .address)
                        .submitLabel(.next)
                        .onSubmit {
                            signIn.tidyAddress()
                            focused = .username
                        }

                    TextField("Username", text: $signIn.username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }

                    SecureField("Password", text: $signIn.password)
                        .textContentType(.password)
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { if signIn.canConnect { connect() } }
                } footer: {
                    Text("Your books play on this device or your speakers, straight from your server, and your place in each one stays in step with the Audiobookshelf apps. Speakers stream from this address too, so it has to be reachable from your network.")
                }

                Section {
                    Button(role: signIn.showsSignOut ? .destructive : nil) {
                        if signIn.showsSignOut {
                            Task { await signIn.signOut() }
                        } else {
                            connect()
                        }
                    } label: {
                        Group {
                            if signIn.isConnecting {
                                ProgressView()
                            } else {
                                Text(signIn.showsSignOut ? "Sign Out" : "Sign In")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(signIn.showsSignOut ? .red : .accentColor)
                    .disabled(!signIn.showsSignOut && !signIn.canConnect)
                    .listRowBackground(Color.clear)
                } footer: {
                    switch signIn.result {
                    case let .failure(message):
                        Text(message).foregroundStyle(.red)
                    case .success where !signIn.hasUnsavedEdits:
                        Text("Signed in. Your books are in the Audiobooks tab.")
                    default:
                        Text("Your login is kept once the server accepts it.")
                    }
                }

                // The server's single sign-on, once its status says it has
                // one.
                if signIn.offersSingleSignOn {
                    Section {
                        Button {
                            connectWithSingleSignOn()
                        } label: {
                            Text(signIn.singleSignOnTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(signIn.isConnecting || signIn.serverAddress.isEmpty)
                        .listRowBackground(Color.clear)
                    } footer: {
                        Text("Signs in through the server's own sign-in page, as its apps do.")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", systemImage: "xmark") { dismiss() }
                }

                ToolbarItem(placement: .principal) {
                    VStack {
                        Text("Audiobookshelf")
                        statusIndicator
                    }
                }
            }
            .onAppear {
                signIn.loadStored()
            }
            .task {
                // A sheet isn't ready for focus on the same pass it appears
                // (see `SubsonicManagementView`).
                guard !signIn.isConfigured else { return }
                try? await Task.sleep(for: .milliseconds(350))
                focused = .address
            }
            // Which ways in the address offers, once typing pauses.
            .task(id: signIn.serverAddress) {
                await signIn.readMethods()
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if signIn.isConnecting {
            ProgressView()
        } else if signIn.isConfigured {
            Text("Signed In")
                .font(.caption.smallCaps())
                .foregroundStyle(.green.gradient)
        }
    }

    private func connect() {
        focused = nil
        Task {
            if await signIn.connect() { signedIn() }
        }
    }

    private func connectWithSingleSignOn() {
        focused = nil
        let session = webAuthenticationSession
        Task {
            if await signIn.connectWithSingleSignOn(using: session) { signedIn() }
        }
    }

    /// Done: the sheet goes, and the banner is the way to the books — the
    /// Audiobooks tab, which the sign-in has just brought in.
    private func signedIn() {
        HapticManager.shared.fireHaptic(.notification(.success))
        dismiss()
        AlertService.shared.showActionAlert(
            with: "Signed In to Audiobookshelf",
            subtitle: "Tap to see your books",
            imageName: "checkmark.circle.fill"
        ) {
            Router.main.presentedSheet = nil
            Router.main.selectedTab = .audiobooks
        }
    }
}

#Preview {
    AudiobookshelfManagementView()
}
