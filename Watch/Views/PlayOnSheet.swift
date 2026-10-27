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
/// can play here (with the headphones it plays to), then the iPhone and
/// each Sonos group it plays to (asked for as it opens), the one playing
/// ticked. A tap hands the choice back and closes it. On the watch's own
/// player, Headphones & Speakers opens the system's Now Playing, whose
/// output button is the only way an app has to offer a choice of output on
/// watchOS (there's no route picker of its own); otherwise watchOS plays to
/// the headphones connected, and asks as playing starts with none.
struct PlayOnSheet: View {
    @Environment(PhoneNowPlaying.self) private var phone
    @Environment(WatchPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    let current: PlayOnChoice?
    let offersWatch: Bool
    var offersOutputs = false
    let choose: (PlayOnChoice) -> Void

    var body: some View {
        NavigationStack {
            List {
                if offersWatch {
                    row(.watch, place: .watch, detail: offersOutputs ? player.output?.name : nil)
                }
                if offersOutputs {
                    NavigationLink {
                        NowPlayingView()
                    } label: {
                        Label("Headphones & Speakers", systemImage: "airplay.audio")
                    }
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

    private func row(_ choice: PlayOnChoice, place: PlaybackPlace, detail: String? = nil) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            dismiss()
            if choice != current {
                choose(choice)
            }
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading) {
                        Text(place.name)
                            .lineLimit(1)
                        if let detail {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } icon: {
                    Image(systemName: place.symbol)
                }
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
