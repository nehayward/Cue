import MusicSearchKit
import SonosKit
import SwiftUI

/// A book's page: its cover, how far in the listener is, Resume, and its
/// chapters, each of which plays the book from there.
///
/// The book is read whole from its server when the page opens; where the
/// server has the listener is taken into `AudiobookProgressStore` (if it's
/// newer than this device's), so the page shows the newer of the two.
struct AudiobookDetailView: View {
    let book: PlayableContent

    @State private var audiobook: Audiobook?
    @State private var failed = false
    @State private var player = AudiobookPlayer.shared
    @State private var store = AudiobookProgressStore.shared

    private var shown: PlayableContent { audiobook?.book ?? book }

    private var progress: AudiobookProgress? {
        store.progress(for: shown)
    }

    /// This book is the one loaded to play.
    private var isCurrent: Bool {
        player.current?.book.id == shown.id && player.current?.book.content.service == shown.content.service
    }

    var body: some View {
        List {
            header
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            actions
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if let summary = audiobook?.summary {
                Section {
                    AudiobookSummary(text: summary)
                }
                .listRowSeparator(.hidden)
            }

            // One chapter is the whole book: nothing to choose between.
            if let audiobook, audiobook.chapters.count > 1 {
                Section {
                    ForEach(audiobook.chapters) { chapter in
                        chapterRow(chapter, in: audiobook)
                    }
                } header: {
                    Text("Chapters")
                }
            }

            if audiobook == nil, !failed {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay {
            if failed, audiobook == nil {
                ContentUnavailableView {
                    Label("Couldn't Open This Book", systemImage: "book.closed")
                } description: {
                    Text("Check that \(book.content.service.title) is reachable, then try again.")
                } actions: {
                    Button("Try Again") { Task { await load() } }
                        .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle(shown.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    finishedButton
                    OpenInServiceView(item: shown)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .disabled(audiobook == nil)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ContentArtworkView(content: shown, showMusicSource: false, preferredSize: ContentArtworkView.playerPreferredSize, cornerRadius: 8)
                // A fixed square: given only a width, the cover took the
                // row's height too and sat in a band of empty space.
                .frame(width: 260, height: 260)
                .overlay(alignment: .bottom) {
                    if let fraction = progress?.fraction, progress?.isStarted == true {
                        AudiobookProgressBar(fraction: fraction, tint: .white, isRounded: false)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .padding(8)
                    }
                }
                .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text(shown.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                if !shown.subtitle.isEmpty {
                    Text(shown.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                if let narrator = audiobook?.narrator {
                    Text("Narrated by \(narrator)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let detail = detailLine {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .fontDesign(.rounded)
        .padding(.top, 8)
    }

    /// "12 hr, 5 min • 3 hr, 2 min left".
    private var detailLine: String? {
        guard let audiobook, audiobook.duration > 0 else { return nil }
        var parts = [AudiobookFormat.duration(audiobook.duration)]
        if let progress, let remaining = AudiobookFormat.remaining(progress) {
            parts.append(remaining)
        }
        return parts.joined(separator: " • ")
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.shared.fireHaptic(.buttonPress)
                Task { await player.play(shown) }
            } label: {
                Group {
                    if player.isLoading {
                        ProgressView()
                    } else {
                        Text("\(Image(systemName: "play.fill")) \(progress?.isStarted == true ? "Resume" : "Play")")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .allowsTightening(true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .glassButton()
            .foregroundStyle(.primary)

            if progress?.isStarted == true || progress?.isFinished == true {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task { await player.play(shown, from: 0) }
                } label: {
                    Text("\(Image(systemName: "backward.end.fill")) From Start")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity)
                }
                .glassButton()
                .foregroundStyle(.primary)
            }
        }
        .bold()
        .fontDesign(.rounded)
        .disabled(audiobook == nil || player.isLoading)
    }

    @ViewBuilder
    private var finishedButton: some View {
        if let audiobook {
            if progress?.isFinished == true {
                Button {
                    Task { await AudiobookLibrary.markFinished(audiobook, false) }
                } label: {
                    Label("Mark as Unfinished", systemImage: "arrow.uturn.backward.circle")
                }
            } else {
                Button {
                    Task { await AudiobookLibrary.markFinished(audiobook, true) }
                } label: {
                    Label("Mark as Finished", systemImage: "checkmark.circle")
                }
            }
        }
    }

    // MARK: - Chapters

    private func chapterRow(_ chapter: AudiobookChapter, in audiobook: Audiobook) -> some View {
        let isPlaying = isCurrent && player.currentChapter?.id == chapter.id
        return Button {
            HapticManager.shared.fireHaptic(.selection)
            Task {
                if isCurrent {
                    await player.jump(to: chapter.start)
                } else {
                    await player.play(audiobook.book, from: chapter.start)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "bookmark")
                    .foregroundStyle(isPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .foregroundStyle(.primary)
                        .fontWeight(isPlaying ? .semibold : .regular)
                    Text(AudiobookFormat.clock(chapter.start))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Text(AudiobookFormat.duration(chapter.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading

    private func load() async {
        failed = false
        guard let loaded = await AudiobookLibrary.load(book) else {
            failed = audiobook == nil
            return
        }
        if let server = loaded.serverProgress {
            store.record(server, for: loaded.book)
        }
        audiobook = loaded
    }
}

/// A book's description: four lines, the last fading out, with More under
/// them, opening out to the whole of it. The text is laid out whole either
/// way and only the frame showing it grows, so it opens as one smooth
/// reveal rather than jumping from one layout of the text to another (a
/// changing `lineLimit` re-wraps it mid-animation).
private struct AudiobookSummary: View {
    let text: String

    @State private var isExpanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var collapsedHeight: CGFloat = 0

    private static let collapsedLines = 4

    private var isMeasured: Bool { fullHeight > 0 && collapsedHeight > 0 }
    private var truncates: Bool { fullHeight > collapsedHeight + 1 }
    private var isCollapsed: Bool { truncates && !isExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: isMeasured ? (isCollapsed ? collapsedHeight : fullHeight) : 0, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .mask {
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: isCollapsed ? 24 : 0)
                    }
                }
                .background(alignment: .top) { measurements }
                .opacity(isMeasured ? 1 : 0)

            if truncates {
                Text(isExpanded ? "Less" : "More")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .contentShape(.rect)
        .onTapGesture {
            guard truncates else { return }
            withAnimation(.smooth(duration: 0.45)) {
                isExpanded.toggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: isExpanded ? "Show Less" : "Show More") {
            isExpanded.toggle()
        }
    }

    /// The text's whole height and its first four lines' at the width it's
    /// shown at, from hidden copies of it.
    private var measurements: some View {
        ZStack(alignment: .top) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            Text(text)
                .lineLimit(Self.collapsedLines)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { collapsedHeight = $0 }
        }
        .hidden()
    }
}
