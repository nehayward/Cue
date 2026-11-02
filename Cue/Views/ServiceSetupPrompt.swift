import MusicSearchKit
import SwiftUI

/// A service's Browse page before it's set up (Plex signed out, no Subsonic
/// or Audiobookshelf server, no Files folder): its tile, what's missing,
/// one prominent way to set it up and, for some, a way to find out more.
/// One look on each, in the type the Audiobooks tab and Browse use for
/// theirs (`ServiceChoiceRow`'s prompts).
struct ServiceSetupPrompt<Extra: View>: View {
    let service: MediaSearchService
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                ServiceMarkTile(service: service, size: 64)
                    .padding(.bottom, 8)
                Text(title)
                    .font(.title2.bold())
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Button {
                HapticManager.shared.fireHaptic(.selection)
                action()
            } label: {
                Text(actionTitle)
                    .font(.headline)
                    .frame(maxWidth: 260)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)

            extra
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        .fontDesign(.rounded)
    }
}

extension ServiceSetupPrompt where Extra == EmptyView {
    init(service: MediaSearchService, title: String, message: String, actionTitle: String, action: @escaping () -> Void) {
        self.init(service: service, title: title, message: message, actionTitle: actionTitle, action: action) {
            EmptyView()
        }
    }
}

/// A link out from a set-up prompt (a server project, the service's site),
/// secondary to its one prominent action.
struct ServiceSetupLink: View {
    let title: String
    let address: String

    var body: some View {
        if let url = URL(string: address) {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Text(title)
                    Image(systemName: "arrow.up.forward")
                        .font(.caption2)
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.accent)
        }
    }
}
