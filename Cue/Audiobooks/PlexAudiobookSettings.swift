import MusicSearchKit
import SonosKit
import SwiftUI

/// Which of the Plex server's Music libraries hold books, and whether books
/// kept in the music library under an audiobook genre count too. Part of
/// the Plex settings sheet.
///
/// Until the listener switches one, the libraries that look like books
/// (named for them, or matched by the Audnexus agent) are on.
struct PlexAudiobookSettingsSection: View {
    /// The selected server, so a switch of server reads its own libraries.
    let serverID: String?

    @State private var choices: [PlexAPI.AudiobookLibrary] = []
    @State private var includesGenreTagged = PlexAPI.shared.includesGenreTaggedAudiobooks

    var body: some View {
        Section {
            ForEach(choices) { choice in
                Toggle(choice.section.title, isOn: Binding(
                    get: { choice.isBooks },
                    set: { set(choice, isBooks: $0) }
                ))
                .tint(.accent)
            }
            Toggle("Books in the Music Library", isOn: $includesGenreTagged)
                .tint(.accent)
                .onChange(of: includesGenreTagged) { _, isOn in
                    PlexAPI.shared.includesGenreTaggedAudiobooks = isOn
                    Task { await AudiobookLibrary.checkPlexBooks(afterChange: true) }
                }
        } header: {
            Text("Audiobooks")
                .font(.headline)
                .foregroundStyle(.secondary)
        } footer: {
            Text("Libraries switched on here show under Audiobooks in the Plex library, played from where you left off. Albums in your music library with the genre Audiobook or Spoken Word show there too. For your place to follow you between Cue and other Plex apps, turn on Store Track Progress in the library's advanced settings on your server.")
        }
        .task(id: serverID) {
            choices = await PlexAPI.shared.audiobookLibraryChoices()
        }
    }

    private func set(_ choice: PlexAPI.AudiobookLibrary, isBooks: Bool) {
        HapticManager.shared.fireHaptic(.selection)
        var keys = Set(choices.filter(\.isBooks).map(\.id))
        if isBooks {
            keys.insert(choice.id)
        } else {
            keys.remove(choice.id)
        }
        PlexAPI.shared.chosenAudiobookLibraryKeys = choices.map(\.id).filter(keys.contains)
        choices = choices.map { PlexAPI.AudiobookLibrary(section: $0.section, isBooks: keys.contains($0.id)) }
        Task { await AudiobookLibrary.checkPlexBooks(afterChange: true) }
    }
}
