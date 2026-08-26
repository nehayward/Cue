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
    @State private var isTesting = false
    @State private var testResult: SubsonicAPI.PingResult?

    private var isConnected: Bool {
        if case .success = testResult { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("https://music.example.com", text: $serverAddress)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } header: {
                    Text("Server Address")
                } footer: {
                    Text("Works with Subsonic, Navidrome, Airsonic and other Subsonic-compatible servers. Your Sonos speakers must be able to reach this address, so prefer the same network (or a publicly reachable HTTPS address).")
                }

                Section("Account") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            } else if let testResult {
                                switch testResult {
                                case .success:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green.gradient)
                                case .failure:
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    .disabled(isTesting || serverAddress.isEmpty || username.isEmpty || password.isEmpty)
                } footer: {
                    if case let .failure(message) = testResult {
                        Text(message)
                            .foregroundStyle(.red)
                    } else if isConnected {
                        Text("Connected. Subsonic now appears in search and browse.")
                    }
                }

                if subsonic.isConfigured {
                    Section {
                        Button("Disconnect", role: .destructive) {
                            serverAddress = ""
                            username = ""
                            password = ""
                            testResult = nil
                            apply()
                            // Mirror the connect path, which enables the
                            // service — otherwise the Settings toggle stays
                            // visually on for a service that can't play.
                            CoreFeatures.shared.enabledServices(.subsonic).wrappedValue = false
                        }
                    }
                }
            }
            .navigationTitle("Subsonic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Text("Subsonic")
                        Image(systemName: subsonic.isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(subsonic.isConfigured ? AnyShapeStyle(.green.gradient) : AnyShapeStyle(.red))
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        apply()
                        dismiss()
                    }
                }
            }
            .onAppear {
                serverAddress = subsonic.serverAddress
                username = subsonic.username
                password = subsonic.password
            }
        }
    }

    /// Writes the edited values through to stored settings — only when they
    /// changed, so the auth salt isn't needlessly rotated.
    private func apply() {
        if subsonic.serverAddress != serverAddress { subsonic.serverAddress = serverAddress }
        if subsonic.username != username { subsonic.username = username }
        if subsonic.password != password { subsonic.password = password }
    }

    private func testConnection() async {
        apply()
        isTesting = true
        testResult = await subsonic.ping()
        isTesting = false
        if isConnected {
            // A working server means the service is authorized — surface it
            // in search/browse right away.
            CoreFeatures.shared.enabledServices(.subsonic).wrappedValue = true
            Task { await SubsonicBrowseService.shared.refresh() }
        }
    }
}

#Preview {
    SubsonicManagementView()
}
