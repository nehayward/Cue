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
        // A scroll view, not a List: a List resizes a row on its own, after
        // the row's content has changed, so the summary opening out jumped
        // however its text was animated.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                actions
                    .padding(.top, 20)

                if audiobook?.filesMissing == true {
                    missingFilesNotice
                        .padding(.top, 20)
                }

                if let summary = audiobook?.summary {
                    AudiobookSummary(text: summary)
                        .padding(.top, 20)
                }

                // One chapter is the whole book: nothing to choose between.
                if let audiobook, audiobook.chapters.count > 1 {
                    Text("Chapters")
                        .font(.title3.bold())
                        .padding(.top, 28)
                        .padding(.bottom, 4)
                    ForEach(audiobook.chapters) { chapter in
                        chapterRow(chapter, in: audiobook)
                        if chapter.id != audiobook.chapters.last?.id {
                            Divider()
                                .padding(.leading, 32)
                        }
                    }
                }

                if audiobook == nil, !failed {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
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
                // New York, a book's own face, for its title. Nothing
                // around it may set a design: the outermost `.fontDesign`
                // wins over one nearer the text, so the lines under it set
                // rounded on themselves.
                Text(shown.title)
                    .font(.title3.bold())
                    .fontDesign(.serif)
                    .multilineTextAlignment(.center)
                Group {
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
                .fontDesign(.rounded)
            }
            .frame(maxWidth: .infinity)
        }
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

            // The whole book on this device, for listening with no network.
            ContainerDownloadButton(item: shown)
                .foregroundStyle(.primary)
        }
        .bold()
        .fontDesign(.rounded)
        .disabled(audiobook == nil || player.isLoading)
    }

    /// The server lists the book but can't open its files, so it won't play
    /// and shows no chapters: said here, where the missing chapters show.
    private var missingFilesNotice: some View {
        let service = book.content.service.title
        return Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(service) Can't Open This Book")
                    .font(.subheadline.bold())
                Text("\(service) lists its files but can't find them, so it won't play or show its chapters. Check that the files are still in the library's folder on the server, then scan the library again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Image(systemName: isPlaying ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isPlaying ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
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
            // The chapter playing is the accent throughout: its levels
            // (primary, secondary) are the accent's.
            .foregroundStyle(isPlaying ? AnyShapeStyle(.tint) : AnyShapeStyle(.foreground))
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPlaying ? .isSelected : [])
    }

    // MARK: - Loading

    private func load() async {
        failed = false
        guard let loaded = await AudiobookLibrary.load(book) else {
            failed = audiobook == nil
            return
        }
        store.recordServerProgress(of: loaded)
        audiobook = loaded
    }
}

/// A book's description: four lines, the last fading out, opening out to
/// the whole of it at a tap anywhere on it, and closing again the same way.
/// The text is laid out whole either way and only the frame showing it
/// grows, so it opens as one smooth reveal rather than jumping from one
/// layout of the text to another (a changing `lineLimit` re-wraps it
/// mid-animation); as a geometry group it reaches the page as a single
/// change of size, which the rows below follow in step.
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
        Text(text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: isMeasured ? (isCollapsed ? collapsedHeight : fullHeight) : 0, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            // The last line fading out says there's more.
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: isCollapsed ? 24 : 0)
                }
            }
            .background(alignment: .top) { measurements }
            .opacity(isMeasured ? 1 : 0)
            .geometryGroup()
            .font(.callout)
            // New York, a reading face at this size.
            .fontDesign(.serif)
            .foregroundStyle(.secondary)
            .contentShape(.rect)
            .onTapGesture(perform: toggle)
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: isExpanded ? "Show Less" : "Show More", toggle)
    }

    private func toggle() {
        guard truncates else { return }
        HapticManager.shared.fireHaptic(.selection)
        withAnimation(.smooth(duration: 0.45)) {
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
