import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The loaded book's chapters, as a sheet from the player's chapter line
/// and its menu: a long book's were a menu taller than the screen. It opens
/// with the chapter playing at the top of the list and keeps it there as
/// chapters change; a chapter picked plays from its start and the sheet
/// goes. Its other page, a swipe or the switch on top
/// away, is the book's place history.
///
/// `inPanel`, it's the player's queue panel while a book plays, in place of
/// Next Up (`QueueNextUpView`): a book's files aren't a queue to reorder,
/// and a book read whole may have one file. The panel stays as a chapter or
/// a place is picked, as it does for a song.
struct AudiobookChaptersView: View {
    var inPanel = false

    @Environment(\.dismiss) private var dismiss
    @State private var player = AudiobookPlayer.shared
    @State private var page = Page.chapters
    /// The panel's pages, side by side in a scroll view that pages.
    @State private var pagePosition = ScrollPosition(idType: Page.self)

    private enum Page: Hashable {
        case chapters
        case history
    }

    var body: some View {
        if inPanel {
            VStack(alignment: .leading, spacing: 0) {
                // Where Next Up has its title and buttons.
                pagePicker
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                panelPage
            }
            .fontDesign(.rounded)
        } else {
            NavigationStack {
                pages
                    .navigationTitle(page == .history ? "History" : "Chapters")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            pagePicker
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
    }

    /// In the panel, the two pages side by side, a swipe or the switch
    /// moving between them, as in the sheet. Not the sheet's paging
    /// `TabView`: made as the panel slid in, it could settle with its pages
    /// out of step with the panel's width, History showing at its edge. Here
    /// each page is the scroll view's own width, and a change of width puts
    /// the page shown back in place.
    private var panelPage: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                chapterList(player.current?.chapters ?? [])
                    .containerRelativeFrame(.horizontal)
                    .id(Page.chapters)
                historyPage
                    .containerRelativeFrame(.horizontal)
                    .id(Page.history)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition($pagePosition)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A swipe sets the switch, and the switch turns the page.
        .onChange(of: pagePosition.viewID(type: Page.self)) { _, shown in
            guard let shown, shown != page else { return }
            page = shown
        }
        .onChange(of: page) { _, page in
            guard pagePosition.viewID(type: Page.self) != page else { return }
            withAnimation(.snappy) {
                pagePosition.scrollTo(id: page)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in
            pagePosition.scrollTo(id: page)
        }
    }

    /// Side by side: a swipe moves between them, as the switch does.
    private var pages: some View {
        TabView(selection: $page) {
            chapterList(player.current?.chapters ?? [])
                .tag(Page.chapters)
            historyPage
                .tag(Page.history)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var pagePicker: some View {
        // The panel turns its page itself (`panelPage`); the sheet's
        // `TabView` follows the switch's animation.
        Picker("Show", selection: inPanel ? $page : $page.animation()) {
            Text("Chapters").tag(Page.chapters)
            Text("History").tag(Page.history)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    /// The sheet goes once something is picked; the panel stays.
    private func picked() {
        if !inPanel { dismiss() }
    }

    @ViewBuilder
    private var historyPage: some View {
        if let book = player.current {
            ScrollView {
                AudiobookHistoryList(book: book.book, audiobook: book) { picked() }
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
                            picked()
                            guard let audiobook = player.current else { return }
                            Task { await player.pick(audiobook.book, at: chapter.start, in: audiobook) }
                        } label: {
                            AudiobookChapterRowLabel(chapter: chapter, isHere: isHere, isDone: here.map { chapter.start < $0.start } ?? false, book: player.current?.book)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isHere ? .isSelected : [])
                        .id(chapter.id)
                        // None against the listener's chapter: its fill
                        // sets it apart, and a line over it at the top of
                        // the list was a stray.
                        if chapter.id != chapters.last?.id, !isHere, chapters.after(chapter)?.id != here?.id {
                            Divider()
                                .padding(.leading, 32)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear {
                guard let playing = player.currentChapter else { return }
                proxy.scrollTo(playing.id, anchor: .top)
            }
            .onChange(of: player.currentChapter?.id) { _, playing in
                guard let playing else { return }
                withAnimation {
                    proxy.scrollTo(playing, anchor: .top)
                }
            }
        }
    }
}
