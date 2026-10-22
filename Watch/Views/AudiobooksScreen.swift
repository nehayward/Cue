import SwiftUI
import WatchSync

/// Audiobooks, the last of the library's lists on the home screen: the
/// books on the watch, to pick up where they were left, then the servers'
/// shelves — what's in progress, and every book on each.
struct AudiobooksScreen: View {
    @Environment(WatchDownloadStore.self) private var store
    @Environment(WatchAccounts.self) private var accounts
    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        List {
            if !store.books.isEmpty {
                Section {
                    ForEach(store.books, id: \.key) { pick in
                        let route = BookRoute(key: pick.key)
                        NavigationLink(value: route) {
                            BookRow(pick: pick)
                        }
                        .zoomSource(route, in: zoom)
                    }
                } header: {
                    Text("On This Watch")
                }
            }
            if accounts.hasBooks {
                Section {
                    shelf(.listening, title: "Continue Listening", symbol: "clock.arrow.circlepath")
                    if accounts.hasPlex, accounts.plexHasBooks {
                        shelf(.all(.plex), title: "Plex Books", symbol: "server.rack")
                    }
                    if accounts.hasAudiobookshelf {
                        shelf(.all(.audiobookshelf), title: "Audiobookshelf", symbol: "book.closed.fill")
                    }
                }
            } else if store.books.isEmpty {
                Text("Choose a Plex library of books, or sign in to Audiobookshelf, in Cue on your iPhone to browse your books here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Audiobooks")
    }

    private func shelf(_ shelf: WatchBookShelf, title: String, symbol: String) -> some View {
        let route = BrowseRoute.path(.books(shelf))
        return NavigationLink(value: route) {
            Label(title, systemImage: symbol)
        }
        .zoomSource(route, in: zoom)
    }
}
