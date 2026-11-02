import MusicSearchKit
import SwiftUI

/// Onboarding's Audiobookshelf page, shown when Audiobookshelf was chosen and
/// isn't signed in: the server's address and login, or its single sign-on
/// once the address says it has one (`AudiobookshelfSignIn`, as Settings'
/// sheet).
struct AudiobookshelfSetupStep: View {
    var advance: () -> Void

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var signIn = AudiobookshelfSignIn()

    private enum Field { case address, username, password }
    @FocusState private var focused: Field?

    var body: some View {
        @Bindable var signIn = signIn
        SetupPage(
            service: .audiobookshelf,
            title: "Connect Audiobookshelf",
            subtitle: "Sign in to your server to listen to your books here and on your speakers.",
            actionTitle: signIn.isConnecting ? "Signing In…" : "Sign In",
            isActionDisabled: !signIn.canConnect,
            action: connect,
            later: advance
        ) {
            VStack(spacing: 10) {
                SetupFieldCard {
                    TextField("Server", text: $signIn.serverAddress, prompt: Text("nas.local:13378"))
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
                    hint: "Your place in each book stays in step with the Audiobookshelf apps."
                )

                // The server's single sign-on, once its status says it has
                // one.
                if signIn.offersSingleSignOn {
                    Button(action: connectWithSingleSignOn) {
                        Text(signIn.singleSignOnTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.1), in: Capsule())
                            .overlay { Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1) }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(signIn.isConnecting)
                    .padding(.top, 8)
                    .transition(.opacity)
                }
            }
        }
        .onAppear { signIn.loadStored() }
        .task(id: signIn.serverAddress) {
            await signIn.readMethods()
        }
    }

    private func connect() {
        focused = nil
        Task { finish(await signIn.connect()) }
    }

    private func connectWithSingleSignOn() {
        focused = nil
        let session = webAuthenticationSession
        Task { finish(await signIn.connectWithSingleSignOn(using: session)) }
    }

    private func finish(_ signedIn: Bool) {
        if signedIn {
            HapticManager.shared.fireHaptic(.notification(.success))
            advance()
        } else {
            HapticManager.shared.fireHaptic(.notification(.error))
        }
    }
}
