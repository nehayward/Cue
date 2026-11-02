import MusicSearchKit
import SwiftUI

/// Onboarding's Subsonic page, shown when Subsonic was chosen and no server
/// is connected yet: the server's address and login, checked against the
/// server before anything is kept (`SubsonicSignIn`, as Settings' sheet).
struct SubsonicSetupStep: View {
    var advance: () -> Void

    @State private var signIn = SubsonicSignIn()

    private enum Field { case address, username, password }
    @FocusState private var focused: Field?

    var body: some View {
        @Bindable var signIn = signIn
        SetupPage(
            service: .subsonic,
            title: "Connect Subsonic",
            subtitle: "Sign in to your Navidrome, Airsonic or other Subsonic server.",
            actionTitle: signIn.isConnecting ? "Connecting…" : "Connect",
            isActionDisabled: !signIn.canConnect,
            action: connect,
            later: advance
        ) {
            VStack(spacing: 10) {
                SetupFieldCard {
                    TextField("Server", text: $signIn.serverAddress, prompt: Text("navidrome.local:4533"))
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
                        .setupField()
                    SetupFieldDivider()
                    TextField("Username", text: $signIn.username, prompt: Text("Username"))
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                        .setupField()
                    SetupFieldDivider()
                    SecureField("Password", text: $signIn.password, prompt: Text("Password"))
                        .textContentType(.password)
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { if signIn.canConnect { connect() } }
                        .setupField()
                }
                SetupFieldNote(
                    error: signIn.failure,
                    hint: "Your speakers stream from this address too, so it has to be reachable on your network."
                )
            }
        }
        .onAppear { signIn.loadStored() }
    }

    private func connect() {
        focused = nil
        Task {
            if await signIn.connect() {
                HapticManager.shared.fireHaptic(.notification(.success))
                advance()
            } else {
                HapticManager.shared.fireHaptic(.notification(.error))
            }
        }
    }
}
