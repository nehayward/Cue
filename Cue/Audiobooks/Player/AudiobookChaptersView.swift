import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The loaded book's chapters, as a sheet from the player's chapter line
/// and its menu: a long book's were a menu taller than the screen. It opens
/// on the chapter playing and follows it; a chapter picked plays from its
/// start and the sheet goes. Its other page, a swipe or the switch on top
/// away, is the book's place history.
struct AudiobookChaptersView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player = AudiobookPlayer.shared
    @State private var page = Page.chapters

    private enum Page: Hashable {
        case chapters
        case history
    }

    var body: some View {
        let chapters = player.current?.chapters ?? []
        NavigationStack {
            // Side by side: a swipe moves between them, as the switch does.
            TabView(selection: $page) {
                chapterList(chapters)
                    .tag(Page.chapters)
                historyPage
                    .tag(Page.history)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle(page == .history ? "History" : "Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $page.animation()) {
                        Text("Chapters").tag(Page.chapters)
                        Text("History").tag(Page.history)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "xmark")
                    }
                }
            }
        }
        .fontDesign(.rounded)
    }

    @ViewBuilder
    private var historyPage: some View {
        if let book = player.current {
            ScrollView {
                AudiobookHistoryList(book: book.book, audiobook: book) { dismiss() }
                    .padding(.horizontal, 20)
            }
        } else {
            Color.clear
        }
    }

    private func chapterList(_ chapters: [AudiobookChapter]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    let here = player.currentChapter
                    ForEach(chapters) { chapter in
                        let isHere = chapter.id == here?.id
                        Button {
                            HapticManager.shared.fireHaptic(.selection)
                            dismiss()
                            Task { await player.play(chapter: chapter) }
                        } label: {
                            AudiobookChapterRowLabel(chapter: chapter, isHere: isHere, isDone: here.map { chapter.start < $0.start } ?? false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isHere ? .isSelected : [])
                        .id(chapter.id)
                        if chapter.id != chapters.last?.id {
                            Divider()
                                .padding(.leading, 32)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear {
                guard let playing = player.currentChapter else { return }
                proxy.scrollTo(playing.id, anchor: .center)
            }
            .onChange(of: player.currentChapter?.id) { _, playing in
                guard let playing else { return }
                withAnimation {
                    proxy.scrollTo(playing, anchor: .center)
                }
            }
        }
    }
}
