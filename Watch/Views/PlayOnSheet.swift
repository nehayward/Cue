import SwiftUI
import WatchKit
import WatchSync

/// A place to play: this watch, or one of the iPhone's routes (itself, or a
/// Sonos group, by `WatchPhoneRoutes.Route.id`).
enum PlayOnChoice: Hashable {
    case watch
    case phone(String)
}

/// Play On, from the place glyph on a player: Apple Watch where what plays
/// can play here, then the iPhone and each Sonos group it plays to (asked
/// for as it opens), the one playing ticked. A tap hands the choice back and
/// closes it.
struct PlayOnSheet: View {
    @Environment(PhoneNowPlaying.self) private var phone
    @Environment(\.dismiss) private var dismiss
    let current: PlayOnChoice?
    let offersWatch: Bool
    let choose: (PlayOnChoice) -> Void

    var body: some View {
        NavigationStack {
            List {
                if offersWatch {
                    row(.watch, place: .watch)
                }
                if phone.isPhoneInReach {
                    if let routes = phone.routes?.routes {
                        ForEach(routes) { route in
                            row(.phone(route.id), place: route.isSpeaker ? .speaker(route.name) : .iPhone)
                        }
                    } else {
                        row(.phone(WatchPhoneRoutes.iPhoneID), place: .iPhone)
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Text("iPhone out of reach")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Play On")
            .task {
                phone.refreshRoutes()
            }
        }
    }

    private func row(_ choice: PlayOnChoice, place: PlaybackPlace) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            dismiss()
            if choice != current {
                choose(choice)
            }
        } label: {
            HStack {
                Label(place.name, systemImage: place.symbol)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if choice == current {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}

/// Moves what the screen pushed over the home screen shows to another
/// player, in its place: the watch's (`.nowPlaying`) or the iPhone's.
struct ShowPlayerKey: EnvironmentKey {
    static let defaultValue: (@MainActor (HomeRoute) -> Void)? = nil
}

extension EnvironmentValues {
    var showPlayer: (@MainActor (HomeRoute) -> Void)? {
        get { self[ShowPlayerKey.self] }
        set { self[ShowPlayerKey.self] = newValue }
    }
}
