import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// A book's bookmarks in book order (`AudiobookBookmarks`): each with its
/// name, the chapter it's in and its time. A tap plays the book from there;
/// a long press renames or takes it away. While the player has the book,
/// Add Bookmark at the top marks where it is.
///
/// On the player's glass sheets, so its dim lines are opacities of
/// `.primary`, not `.secondary`, whose vibrancy flickers as the glass moves.
struct AudiobookBookmarkList: View {
    let book: PlayableContent
    /// The book read whole, for its chapters' names; nil before it's read.
    let audiobook: Audiobook?
    /// After a bookmark is picked: the sheet showing the list closes.
    var onPick: () -> Void = {}

    @State private var store = AudiobookBookmarks.shared
    @State private var player = AudiobookPlayer.shared
    @State private var renaming: AudiobookBookmarks.Bookmark?
    @State private var draft = ""

    var body: some View {
        let marks = store.bookmarks(for: book)
        VStack(alignment: .leading, spacing: 0) {
            if player.isLoaded(book) {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    player.addBookmark()
                } label: {
                    Label("Add Bookmark", systemImage: "bookmark.badge.plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .glassButton()
                .foregroundStyle(.primary)
                .padding(.vertical, 10)
            }
            if marks.isEmpty {
                ContentUnavailableView {
                    Label("No Bookmarks", systemImage: "bookmark")
                } description: {
                    Text("Mark a place to come back to from the player's menu, or with Add Bookmark here.")
                }
                .padding(.top, 24)
            } else {
                ForEach(marks) { mark in
                    row(mark)
                    if mark.id != marks.last?.id {
                        Divider()
                            .padding(.leading, 32)
                    }
                }
            }
        }
        .alert("Rename Bookmark", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $draft)
            Button("Save") {
                if let renaming {
                    store.rename(renaming, to: draft, in: book)
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) {
                renaming = nil
            }
        }
    }

    private func row(_ mark: AudiobookBookmarks.Bookmark) -> some View {
        Button {
            HapticManager.shared.fireHaptic(.selection)
            onPick()
            Task { await player.pick(book, at: mark.position, in: audiobook) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mark.title)
                        .lineLimit(2)
                    Text(detail(of: mark))
                        .font(.footnote)
                        .foregroundStyle(.primary.opacity(0.6))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                draft = mark.title
                renaming = mark
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                HapticManager.shared.fireHaptic(.selection)
                store.remove(mark, from: book)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityHint("Plays from here")
    }

    /// "Chapter 3 · 1:02:15", the chapter left out when it's the name.
    private func detail(of mark: AudiobookBookmarks.Bookmark) -> String {
        let time = AudiobookFormat.clock(mark.position)
        guard let audiobook, audiobook.chapters.count > 1,
              let chapter = audiobook.chapter(at: mark.position), chapter.title != mark.title else { return time }
        return "\(chapter.title) · \(time)"
    }
}

extension AudiobookPlayer {
    /// Marks where the loaded book is, named for its chapter, and says so.
    func addBookmark() {
        guard let current else { return }
        let title = AudiobookBookmarks.defaultTitle(at: position, in: current)
        AudiobookBookmarks.shared.add(at: position, title: title, to: current.book)
        AlertService.shared.showAlert(with: "Bookmark Added", imageName: "bookmark.fill")
    }
}
