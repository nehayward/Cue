import MusicSearchKit
import SwiftUI
import SonosKit

/// Connection settings for a Subsonic-compatible server (Subsonic, Navidrome,
/// Airsonic, Gonic, …). Unlike the streaming services there is no Sonos-side
/// account: the credentials entered here are the whole setup, and the
/// speakers stream straight from the server.
struct SubsonicManagementView: View {
    @Environment(\.dismiss) private var dismiss

    /// The fields and the sign-in itself, shared with onboarding's page.
    @State private var signIn = SubsonicSignIn()

    private enum Field { case address, username, password }
    @FocusState private var focused: Field?

    var body: some View {
        @Bindable var signIn = signIn
        NavigationStack {
            List {
                Section {
                    TextField("navidrome.local:4533", text: $signIn.serverAddress)
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
                    Text("Works with Navidrome, Airsonic, Gonic and other Subsonic-compatible servers. Your speakers stream from this address too, so it has to be reachable from your network.")
                }

                Section {
                    Button(role: signIn.showsDisconnect ? .destructive : nil) {
                        if signIn.showsDisconnect {
                            signIn.disconnect()
                        } else {
                            connect()
                        }
                    } label: {
                        Group {
                            if signIn.isConnecting {
                                ProgressView()
                            } else {
                                Text(signIn.showsDisconnect ? "Disconnect" : "Connect")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(signIn.showsDisconnect ? .red : .accentColor)
                    .disabled(!signIn.showsDisconnect && !signIn.canConnect)
                    .listRowBackground(Color.clear)
                } footer: {
                    switch signIn.result {
                    case let .failure(message):
                        Text(message).foregroundStyle(.red)
                    case .success where !signIn.hasUnsavedEdits:
                        Text("Connected. Subsonic now appears in search and browse.")
                    default:
                        Text("Your login is saved once the server accepts it.")
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
                        Text("Subsonic")
                        statusIndicator
                    }
                }
            }
            .onAppear {
                signIn.loadStored()
            }
            .task {
                // A sheet isn't ready for focus on the same runloop pass it
                // appears; without the hop the keyboard never comes up. Read
                // the stored value, not the @State copy `onAppear` fills —
                // SwiftUI doesn't order the two, so the copy may still be
                // empty for a configured server.
                guard !signIn.isConfigured else { return }
                try? await Task.sleep(for: .milliseconds(350))
                focused = .address
            }
        }
    }

    /// Whether a server is currently set up — the *persistent* state, which
    /// is why a failed attempt doesn't show here: the last attempt's outcome
    /// is transient and belongs next to the button that caused it, where it
    /// can also say what actually went wrong. Duplicating it as a generic
    /// "connection failed" under the title only says it twice, less usefully.
    @ViewBuilder
    private var statusIndicator: some View {
        if signIn.isConnecting {
            ProgressView()
        } else if signIn.isConfigured {
            Text("Connected")
                .font(.caption.smallCaps())
                .foregroundStyle(.green.gradient)
        }
    }

    private func connect() {
        focused = nil
        Task { await signIn.connect() }
    }
}

#Preview {
    SubsonicManagementView()
}
