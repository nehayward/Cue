import MusicSearchKit
import SwiftUI
import SonosKit

/// Sign-in for an Audiobookshelf server. Like Subsonic, there's no
/// Sonos-side account: the login entered here is the whole setup, and the
/// device or a speaker plays the books straight from the server.
///
/// The password is only sent to sign in. What's kept is the server's
/// tokens, in the keychain (see `AudiobookshelfAPI`).
struct AudiobookshelfManagementView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var shelf = AudiobookshelfAPI.shared
    @State private var serverAddress: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isConnecting = false
    @State private var result: AudiobookshelfAPI.LoginResult?

    private enum Field { case address, username, password }
    @FocusState private var focused: Field?

    private var canConnect: Bool {
        !isConnecting && !serverAddress.isEmpty && !username.isEmpty
    }

    /// A different server or user than the one signed in, so there's a
    /// sign-in to make. The password isn't kept, so it doesn't count.
    private var hasUnsavedEdits: Bool {
        serverAddress != shelf.serverAddress || username != shelf.username || !password.isEmpty
    }

    /// One action, never both, as on the Subsonic sheet.
    private var showsSignOut: Bool {
        shelf.isConfigured && !(hasUnsavedEdits && canConnect)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("nas.local:13378", text: $serverAddress)
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
                    Text("Your books play on this device or your speakers, straight from your server, and your place in each one stays in step with the Audiobookshelf apps. Speakers stream from this address too, so it has to be reachable from your network.")
                }

                Section {
                    Button(role: showsSignOut ? .destructive : nil) {
                        if showsSignOut {
                            Task { await signOut() }
                        } else {
                            Task { await connect() }
                        }
                    } label: {
                        Group {
                            if isConnecting {
                                ProgressView()
                            } else {
                                Text(showsSignOut ? "Sign Out" : "Sign In")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(showsSignOut ? .red : .accentColor)
                    .disabled(!showsSignOut && !canConnect)
                    .listRowBackground(Color.clear)
                } footer: {
                    switch result {
                    case let .failure(message):
                        Text(message).foregroundStyle(.red)
                    case .success where !hasUnsavedEdits:
                        Text("Signed in. Your books are in the Audiobooks tab.")
                    default:
                        Text("Your login is kept once the server accepts it.")
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
                serverAddress = shelf.serverAddress
                username = shelf.username
            }
            .task {
                // A sheet isn't ready for focus on the same pass it appears
                // (see `SubsonicManagementView`).
                guard shelf.serverAddress.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(350))
                focused = .address
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if isConnecting {
            ProgressView()
        } else if shelf.isConfigured {
            Text("Signed In")
                .font(.caption.smallCaps())
                .foregroundStyle(.green.gradient)
        }
    }

    /// Reduces a pasted browser URL to the server's root, in place. A
    /// scheme the user didn't type stays off until signing in settles it.
    private func tidyAddress() {
        guard var tidied = AudiobookshelfURLs.normalizedAddress(serverAddress) else { return }
        if !serverAddress.contains("://"), tidied.hasPrefix("http://") {
            tidied.removeFirst("http://".count)
        }
        serverAddress = tidied
    }

    private func connect() async {
        focused = nil
        tidyAddress()
        isConnecting = true
        let check = await shelf.signIn(address: serverAddress, username: username, password: password)
        isConnecting = false
        result = check.result
        guard check.result == .success, let address = check.address else { return }
        serverAddress = address
        password = ""
        CoreFeatures.shared.enabledServices(.audiobookshelf).wrappedValue = true
        Task { await AudiobookshelfBrowseService.shared.refresh() }
        // Done: the sheet goes, and the banner is the way to the books — the
        // Audiobooks tab, which the sign-in has just brought in.
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

    private func signOut() async {
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

#Preview {
    AudiobookshelfManagementView()
}
