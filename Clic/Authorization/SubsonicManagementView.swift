import MusicSearchKit
import SwiftUI
import SonosKit

/// Connection settings for a Subsonic-compatible server (Subsonic, Navidrome,
/// Airsonic, Gonic, …). Unlike the streaming services there is no Sonos-side
/// account: the credentials entered here are the whole setup, and the
/// speakers stream straight from the server.
struct SubsonicManagementView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var subsonic = SubsonicAPI.shared
    @State private var serverAddress: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isConnecting = false
    @State private var result: SubsonicAPI.PingResult?

    private enum Field { case address, username, password }
    @FocusState private var focused: Field?

    private var canConnect: Bool {
        !isConnecting && !serverAddress.isEmpty && !username.isEmpty && !password.isEmpty
    }

    /// Fields differ from what's stored, so there is something to save.
    private var hasUnsavedEdits: Bool {
        serverAddress != subsonic.serverAddress
            || username != subsonic.username
            || password != subsonic.password
    }

    /// One action, never both: a connected server with no pending edits
    /// offers Disconnect, anything else offers Connect — so editing a saved
    /// login still gives you a way to save it.
    private var showsDisconnect: Bool {
        subsonic.isConfigured && !hasUnsavedEdits
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("navidrome.local:4533", text: $serverAddress)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused, equals: .address)
                        .submitLabel(.next)
                        .onSubmit {
                            tidyAddress()
                            focused = .username
                        }

                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { if canConnect { Task { await connect() } } }
                } footer: {
                    Text("Works with Navidrome, Airsonic, Gonic and other Subsonic-compatible servers. Your speakers stream from this address too, so it has to be reachable from your network.")
                }

                Section {
                    Button(role: showsDisconnect ? .destructive : nil) {
                        if showsDisconnect {
                            disconnect()
                        } else {
                            Task { await connect() }
                        }
                    } label: {
                        Group {
                            if isConnecting {
                                ProgressView()
                            } else {
                                Text(showsDisconnect ? "Disconnect" : "Connect")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(showsDisconnect ? .red : .accentColor)
                    .disabled(!showsDisconnect && !canConnect)
                    .listRowBackground(Color.clear)
                } footer: {
                    switch result {
                    case let .failure(message):
                        Text(message).foregroundStyle(.red)
                    case .success where !hasUnsavedEdits:
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
                serverAddress = subsonic.serverAddress
                username = subsonic.username
                password = subsonic.password
            }
            .task {
                // A sheet isn't ready for focus on the same runloop pass it
                // appears; without the hop the keyboard never comes up.
                guard serverAddress.isEmpty else { return }
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
        if isConnecting {
            ProgressView()
        } else if subsonic.isConfigured {
            Text("Connected")
                .font(.caption.smallCaps())
                .foregroundStyle(.green.gradient)
        }
    }

    /// Reduces a pasted browser URL to the server's REST root, in place, so
    /// the field shows the address that will actually be used.
    private func tidyAddress() {
        guard let tidied = SubsonicAPI.normalizedAddress(serverAddress) else { return }
        serverAddress = tidied
    }

    /// Verifies the login against the server and stores it only if the server
    /// accepts it — a rejected password never replaces a working one.
    private func connect() async {
        focused = nil
        tidyAddress()
        isConnecting = true
        let outcome = await subsonic.ping(address: serverAddress, username: username, password: password)
        isConnecting = false
        result = outcome
        guard outcome == .success else { return }

        subsonic.serverAddress = serverAddress
        subsonic.username = username
        subsonic.password = password
        // A working server means the service is authorized — surface it in
        // search and browse right away.
        CoreFeatures.shared.enabledServices(.subsonic).wrappedValue = true
        Task { await SubsonicBrowseService.shared.refresh() }
    }

    private func disconnect() {
        serverAddress = ""
        username = ""
        password = ""
        result = nil
        subsonic.serverAddress = ""
        subsonic.username = ""
        subsonic.password = ""
        // Mirror the connect path, which enables the service — otherwise the
        // Settings toggle stays visually on for a service that can't play.
        CoreFeatures.shared.enabledServices(.subsonic).wrappedValue = false
    }
}

#Preview {
    SubsonicManagementView()
}
