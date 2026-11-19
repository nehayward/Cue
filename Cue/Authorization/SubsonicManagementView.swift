import MusicSearchKit
import SwiftUI
import SonosKit

/// Connection settings for a Subsonic-compatible server (Subsonic, Navidrome,
/// Airsonic, Gonic, …). Unlike the streaming services there is no Sonos-side
/// account: the credentials entered here are the whole setup, and the
/// speakers stream straight from the server.
///
/// Laid out as the set-up prompts are (`ServiceSetupPrompt`): the service's
/// tile over where it stands, then the login as labelled rows, so a field
/// that's filled in still says what it is. A login the server accepts closes
/// the sheet and says so in a toast.
struct SubsonicManagementView: View {
    @Environment(\.dismiss) private var dismiss

    /// The fields and the sign-in itself, shared with onboarding's page.
    @State private var signIn = SubsonicSignIn()
    @State private var showsPassword = false
    @State private var confirmsDisconnect = false

    private enum Field { case address, username, password }
    @FocusState private var focused: Field?

    /// The labels' column, so the fields start in line.
    @ScaledMetric(relativeTo: .body) private var labelWidth: CGFloat = 92

    /// The server as people know it: "Navidrome" once it has said.
    private var serverTitle: String {
        signIn.serverName ?? "Subsonic"
    }

    var body: some View {
        @Bindable var signIn = signIn
        NavigationStack {
            List {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))

                Section {
                    row("Server") {
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
                    }

                    row("Username") {
                        TextField("Required", text: $signIn.username)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focused, equals: .username)
                            .submitLabel(.next)
                            .onSubmit { focused = .password }
                    }

                    row("Password") {
                        passwordField
                    }
                } footer: {
                    Text("Your speakers stream from this address too, so it has to be reachable from your network.")
                }
                .disabled(signIn.isConnecting)

                if let failure = signIn.failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                if signIn.showsDisconnect {
                    Section {
                        Button(role: .destructive) {
                            confirmsDisconnect = true
                        } label: {
                            Text("Disconnect")
                                .frame(maxWidth: .infinity)
                        }
                        // On the button, so on iPad it points at it.
                        .confirmationDialog("Disconnect from \(serverTitle)?", isPresented: $confirmsDisconnect, titleVisibility: .visible) {
                            Button("Disconnect", role: .destructive, action: disconnect)
                        } message: {
                            Text("Cue forgets this server and your login, and Subsonic leaves search and browse.")
                        }
                    }
                } else if !signIn.isConfigured {
                    Section {
                        serverLinks
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .contentMargins(.top, 0, for: .scrollContent)
            // Above the keyboard while typing, where the fields' Go is too.
            .safeAreaInset(edge: .bottom) {
                if !signIn.showsDisconnect {
                    connectButton
                }
            }
            .animation(.smooth, value: signIn.failure)
            .animation(.smooth, value: signIn.showsDisconnect)
            .animation(.smooth, value: signIn.serverName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", systemImage: "xmark") { dismiss() }
                }
            }
            .onChange(of: [signIn.serverAddress, signIn.username, signIn.password]) {
                signIn.clearFailure()
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
                guard !signIn.isConfigured else {
                    // A login saved before Cue kept the server's name.
                    await signIn.refreshServerName()
                    return
                }
                try? await Task.sleep(for: .milliseconds(350))
                focused = .address
            }
            .fontDesign(.rounded)
        }
    }

    /// The tile, and where things stand: connected (to which server, once it
    /// has said), or what this is for.
    private var header: some View {
        VStack(spacing: 8) {
            ServiceMarkTile(service: .subsonic, size: 64)
                .padding(.bottom, 4)
            Text("Subsonic")
                .font(.title2.bold())
            if signIn.isConfigured {
                connectedBadge
            } else {
                Text("Play your own music from Navidrome, Airsonic, gonic or another Subsonic server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// The *stored* login's state, which is why a failed attempt doesn't
    /// show here: that one belongs under the fields, where it can say what
    /// went wrong.
    private var connectedBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
            Text(signIn.serverName.map { "Connected to \($0)" } ?? "Connected")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.green)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.green.opacity(0.15), in: .capsule)
    }

    /// A field after its label, the labels in one column.
    private func row<Content: View>(_ label: String, @ViewBuilder field: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: labelWidth, alignment: .leading)
            field()
        }
    }

    /// The password, hidden or shown with the eye at its end.
    private var passwordField: some View {
        @Bindable var signIn = signIn
        return HStack(spacing: 8) {
            Group {
                if showsPassword {
                    TextField("Required", text: $signIn.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField("Required", text: $signIn.password)
                }
            }
            .textContentType(.password)
            .focused($focused, equals: .password)
            .submitLabel(.go)
            .onSubmit { if signIn.canConnect { connect() } }

            if !signIn.password.isEmpty {
                Button(showsPassword ? "Hide Password" : "Show Password", systemImage: showsPassword ? "eye.slash" : "eye") {
                    showsPassword.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var connectButton: some View {
        Button(action: connect) {
            HStack(spacing: 8) {
                if signIn.isConnecting {
                    ProgressView()
                        .tint(.white)
                    Text("Connecting…")
                } else {
                    Text("Connect")
                }
            }
            .font(.headline)
            .frame(maxWidth: 320)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .disabled(!signIn.canConnect)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    /// For someone with no server yet, as Subsonic's Browse page offers.
    private var serverLinks: some View {
        VStack(spacing: 10) {
            Text("Don't have a server yet?")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ServiceSetupLink(title: "Navidrome", address: "https://www.navidrome.org")
                ServiceSetupLink(title: "Airsonic", address: "https://airsonic.github.io")
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Once the server accepts the login, the sheet closes and a toast says
    /// which server it reached.
    private func connect() {
        guard signIn.canConnect else { return }
        focused = nil
        Task {
            guard await signIn.connect() else {
                HapticManager.shared.fireHaptic(.notification(.error))
                return
            }
            HapticManager.shared.fireHaptic(.notification(.success))
            dismiss()
            AlertService.shared.showAlert(with: "Connected to \(signIn.serverName ?? "Subsonic")", imageName: "checkmark.circle.fill")
        }
    }

    private func disconnect() {
        showsPassword = false
        signIn.disconnect()
        focused = .address
    }
}

#Preview {
    SubsonicManagementView()
}
