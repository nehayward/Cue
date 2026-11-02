import MusicSearchKit
import SwiftUI

/// Onboarding's Files page, shown when Files was chosen and no folder is:
/// what Cue reads from a folder, and the system's folder picker
/// (`FilesFolderChoice`, as Settings' sheet).
struct FilesSetupStep: View {
    var advance: () -> Void

    var body: some View {
        SetupPage(
            service: .files,
            title: "Choose a Folder",
            subtitle: "Pick a folder of music or audiobooks. It plays right here on this device.",
            actionTitle: "Choose Folder",
            actionIcon: "folder.badge.plus",
            action: chooseFolder,
            later: advance
        ) {
            VStack(alignment: .leading, spacing: 16) {
                point("folder", "On this device, in iCloud Drive, or anywhere the Files app opens.")
                point("music.note", "MP3, AAC, ALAC, FLAC, WAV and AIFF, by their tags or folders.")
                point("books.vertical", "Audiobooks too: an album with an .m4b in it.")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                shape
                    .fill(.white.opacity(0.08))
                    .overlay { shape.strokeBorder(.white.opacity(0.12), lineWidth: 1) }
            }
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(MediaSearchService.files.brandColor)
                .frame(width: 24)
        }
    }

    private func chooseFolder() {
        FilesFolderChoice.present { chosen in
            guard chosen else { return }
            HapticManager.shared.fireHaptic(.notification(.success))
            advance()
        }
    }
}
