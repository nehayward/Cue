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
                    Button {
                        Task { await connect() }
                    } label: {
                        if isConnecting {
                            ProgressView()
                        } else {
                            Text(subsonic.isConfigured ? "Reconnect" : "Connect")
                        }
                    }
                    .disabled(!canConnect)
                } footer: {
                    switch result {
                    case let .failure(message):
                        Text(message).foregroundStyle(.red)
                    case .success:
                        Text("Connected. Subsonic now appears in search and browse.")
                    case nil:
                        Text("Your login is saved once the server accepts it.")
                    }
                }

                if subsonic.isConfigured {
                    Section {
                        Button("Disconnect", role: .destructive, action: disconnect)
                    }
                }
            }
            .navigationTitle("Subsonic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", systemImage: "xmark") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    statusIndicator
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

    /// Connection state, in the trailing toolbar so the title stays the title.
    /// A neutral dashed circle before the first attempt — nothing is wrong
    /// yet, it just isn't set up; red is reserved for an actual failure.
    @ViewBuilder
    private var statusIndicator: some View {
        if isConnecting {
            ProgressView()
        } else if case .failure = result {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Connection failed")
        } else if subsonic.isConfigured {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green.gradient)
                .accessibilityLabel("Connected")
        } else {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Not connected")
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
