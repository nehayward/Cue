import MusicSearchKit
import SonosKit
import SwiftUI

/// Signs in to TIDAL, or out. The account is Cue's own, through TIDAL's SDK,
/// not the one linked in the Sonos app: it's what plays TIDAL on this device,
/// and what reads the collection the TIDAL library shows. Speakers play TIDAL
/// through the account linked in the Sonos app.
struct TidalManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var account = TidalAccount.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(role: account.isSignedIn ? .destructive : nil) {
                        if account.isSignedIn {
                            account.signOut()
                        } else {
                            Task { await account.signIn() }
                        }
                    } label: {
                        Group {
                            if account.isSigningIn {
                                ProgressView()
                            } else {
                                Text(account.isSignedIn ? "Sign Out" : "Sign In to Tidal")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(account.isSignedIn ? .red : .accentColor)
                    .disabled(account.isSigningIn || !TidalAccount.isAvailable)
                    .listRowBackground(Color.clear)
                } footer: {
                    if let error = account.signInError {
                        Text(error).foregroundStyle(.red)
                    } else if !TidalAccount.isAvailable {
                        Text("Tidal isn’t available in this version of Cue.")
                    } else if account.isSignedIn {
                        Text("Signed in. Tidal appears in search and in your library, and plays on this device.")
                    } else {
                        Text("Sign in with your Tidal account to search Tidal, see your collection and play it here.")
                    }
                }

                Section {
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        // Only once a song has actually come back as a
                        // preview, with TIDAL's reason for it.
                        if let notice = account.previewNotice {
                            Text(notice)
                        }
                        Text("To play Tidal on your speakers, link Tidal in the Sonos app too.")
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
                        Text("Tidal")
                        if account.isSignedIn {
                            Text("Signed In")
                                .font(.caption.smallCaps())
                                .foregroundStyle(.green.gradient)
                        }
                    }
                }
            }
            .onAppear { account.configure() }
        }
    }
}

#Preview {
    TidalManagementView()
}
