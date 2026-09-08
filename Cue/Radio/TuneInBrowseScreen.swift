import MusicSearchKit
import SonosKit
import SwiftUI

/// A page of TuneIn's directory: stations to play and links to further
/// pages, in the groups TuneIn arranges them in. Links push another of
/// these, so the whole directory is reachable from the Radio tab's four
/// top-level rows.
struct TuneInBrowseScreen: View {
    let title: String
    let url: URL

    @Environment(TuneInBrowseService.self) private var tuneInBrowseService

    @State private var entries: [TuneInBrowseEntry] = []
    @State private var isLoading = true

    var body: some View {
        List {
            ForEach(entries) { entry in
                switch entry {
                case let .group(groupTitle, groupEntries):
                    Section {
                        ForEach(Self.flattened(groupEntries)) { inner in
                            row(inner)
                        }
                    } header: {
                        Text(groupTitle)
                    }
                default:
                    row(entry)
                }
            }
        }
        .fontDesign(.rounded)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .navigationTitle(title)
        .overlay {
            if isLoading, entries.isEmpty {
                ProgressView()
            } else if entries.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Here", systemImage: "radio")
                } description: {
                    Text("TuneIn has no stations on this page right now.")
                }
            }
        }
        .task {
            entries = await tuneInBrowseService.browse(url: url)
            isLoading = false
        }
        .miniPlayerOnScrollHandler()
    }

    @ViewBuilder
    private func row(_ entry: TuneInBrowseEntry) -> some View {
        switch entry {
        case let .station(item):
            PlayableContentView(item: item)
        case let .link(linkTitle, linkURL):
            NavigationLink(value: RouterDestination.tuneInBrowse(title: linkTitle, url: linkURL)) {
                Text(linkTitle)
            }
        case let .group(groupTitle, _):
            // Groups are sections; the rows inside a section are flattened
            // before they get here, so this is never reached.
            Text(groupTitle)
        }
    }

    /// Groups inside a group become plain rows: one level of sections
    /// reads fine, and TuneIn rarely nests deeper than that.
    private static func flattened(_ entries: [TuneInBrowseEntry]) -> [TuneInBrowseEntry] {
        entries.flatMap { entry -> [TuneInBrowseEntry] in
            if case let .group(_, inner) = entry {
                return flattened(inner)
            }
            return [entry]
        }
    }
}

#Preview {
    NavigationStack {
        TuneInBrowseScreen(title: "Music", url: TuneInBrowsePage.music.url)
    }
    .withEnvironments()
}
